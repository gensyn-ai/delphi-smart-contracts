// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IDelphiFactory} from "./IDelphiFactory.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";

/// @title DelphiFactory
/// @notice Deploys Delphi market proxies as EIP-1167 minimal clones of a fixed implementation,
///         funds them with the creator's initial deposit, and keeps the registry of valid markets.
/// @dev The gateway validates every market against this registry (`marketProxyExists`), making the
///      factory the integrity boundary of the system: markets must only be creatable through it.
contract DelphiFactory is IDelphiFactory {
    // ========== CONSTANTS ==========
    /// @dev A zero market-creation fee is permitted by design, but is only valid when SETTLEMENT_FEES
    ///      (KEEPER_FEE + ORACLE_FEE on the market implementation) are also zero — the constructor enforces
    ///      `SETTLEMENT_FEES <= MARKET_CREATION_FEE`. In practice a zero fee is therefore a local-dev/test
    ///      configuration; production deployments that charge keeper/oracle fees must set a market-creation
    ///      fee that covers them.
    uint256 internal constant _MIN_MARKET_CREATION_FEE_18 = 0;
    uint256 internal constant _MAX_MARKET_CREATION_FEE_18 = 100e18;

    // ========== IMMUTABLES ==========

    address public immutable override IMPLEMENTATION;
    IERC20Metadata public immutable override TOKEN;
    uint256 public immutable override MARKET_CREATION_FEE;
    uint256 public immutable override SETTLEMENT_FEES;
    address public immutable override MARKET_CREATION_FEE_RECIPIENT;

    // ========== STATE VARIABLES ==========

    EnumerableSet.AddressSet internal _marketProxies;

    // ========== LIBRARIES ==========
    using EnumerableSet for EnumerableSet.AddressSet;
    using Clones for address;
    using SafeERC20 for IERC20Metadata;

    // ========== CONSTRUCTOR ==========

    /// @notice Deploys the factory for a given market implementation.
    /// @param implementation The market implementation to clone (must be a contract).
    /// @param marketCreationFee The fee charged on market creation, in token decimals. Must cover the
    ///        implementation's settlement fees (KEEPER_FEE + ORACLE_FEE) and be at most 100 tokens.
    /// @param marketCreationFeeRecipient The address that receives the fee remainder after settlement fees.
    constructor(address implementation, uint256 marketCreationFee, address marketCreationFeeRecipient) {
        // Checks: Validate implementation
        if (implementation == address(0)) {
            revert ImplementationIsZeroAddress();
        }
        if (implementation.code.length == 0) {
            revert ImplementationIsNotAContract(implementation);
        }

        // Get token
        IERC20Metadata token = IDelphiMarket(implementation).TOKEN();

        // Calculate token decimal scaler
        uint256 tokenDecimalScaler = 10 ** (18 - token.decimals());

        // Calculate market creation fee bounds
        uint256 minMarketCreationFee = _MIN_MARKET_CREATION_FEE_18 / tokenDecimalScaler;
        uint256 maxMarketCreationFee = _MAX_MARKET_CREATION_FEE_18 / tokenDecimalScaler;

        // Checks: Validate market creation fee
        if (marketCreationFee < minMarketCreationFee) {
            revert MarketCreationFeeIsTooLow(marketCreationFee, minMarketCreationFee);
        }
        if (marketCreationFee > maxMarketCreationFee) {
            revert MarketCreationFeeIsTooHigh(marketCreationFee, maxMarketCreationFee);
        }

        // Checks: Validate market creation fee recipient
        if (marketCreationFeeRecipient == address(0)) {
            revert MarketCreationFeeRecipientIsZeroAddress();
        }

        // Read settlement fees (keeper + oracle) from the market implementation
        uint256 settlementFees = ILmsrMarket(implementation).KEEPER_FEE() + ILmsrMarket(implementation).ORACLE_FEE();

        // Checks: Validate settlement fees are covered by the market creation fee
        if (settlementFees > marketCreationFee) {
            revert SettlementFeesExceedMarketCreationFee(settlementFees, marketCreationFee);
        }

        // Effects: Set immutables
        IMPLEMENTATION = implementation;
        TOKEN = token;
        MARKET_CREATION_FEE = marketCreationFee;
        SETTLEMENT_FEES = settlementFees;
        MARKET_CREATION_FEE_RECIPIENT = marketCreationFeeRecipient;
    }

    // ========== FUNCTIONS ==========

    /// @inheritdoc IDelphiFactory
    function deployNewMarketProxy(
        uint256 initialDeposit_,
        ILmsrMarketTypes.MarketConfig calldata newMarketConfig_,
        IDelphiMarket.VerifiableUri calldata newMarketMetadata_
    ) external returns (address newMarketProxy) {
        // Interactions: Deploy new market proxy
        newMarketProxy = IMPLEMENTATION.clone();

        // Interactions: Pull initial deposit into new market proxy
        TOKEN.safeTransferFrom(msg.sender, newMarketProxy, initialDeposit_);

        // Interactions: Initialize new market proxy
        IDelphiMarket(newMarketProxy)
            .initialize({
                marketCreator_: msg.sender, newMarketConfig_: newMarketConfig_, newMarketMetadata_: newMarketMetadata_
            });

        // Effects: Save new market proxy
        _marketProxies.add(newMarketProxy);

        // Effects: Emit event
        emit NewMarketProxy(msg.sender, IMPLEMENTATION, newMarketProxy, newMarketConfig_, newMarketMetadata_);

        // Distribute market creation fee
        if (MARKET_CREATION_FEE > 0) {
            // Forward settlement fees to the market proxy
            if (SETTLEMENT_FEES > 0) {
                TOKEN.safeTransferFrom(msg.sender, newMarketProxy, SETTLEMENT_FEES);
            }

            // Forward the remainder to the market creation fee recipient
            uint256 recipientFee = MARKET_CREATION_FEE - SETTLEMENT_FEES;
            if (recipientFee > 0) {
                TOKEN.safeTransferFrom(msg.sender, MARKET_CREATION_FEE_RECIPIENT, recipientFee);
            }
        }
    }

    // ========== VIEWS ==========

    // Market Proxies

    /// @inheritdoc IDelphiFactory
    function getTotalMarketProxiesCount() external view returns (uint256) {
        return _marketProxies.length();
    }

    /// @inheritdoc IDelphiFactory
    function getMarketProxies(uint256 firstIdx, uint256 lastIdx) external view returns (address[] memory) {
        if (firstIdx > lastIdx) {
            revert FirstIdxExceedsLastIdx(firstIdx, lastIdx);
        }

        uint256 marketProxyCount = _marketProxies.length();

        if (lastIdx >= marketProxyCount) {
            revert LastIdxOutOfBounds(lastIdx, marketProxyCount);
        }

        return _marketProxies.values(firstIdx, lastIdx + 1); // Note: 2nd arg is exclusive (hence +1)
    }

    /// @inheritdoc IDelphiFactory
    function marketProxyExists(address marketProxy) public view returns (bool) {
        return _marketProxies.contains(marketProxy);
    }

    /// @inheritdoc IDelphiFactory
    function marketProxiesExist(address[] calldata marketProxies) external view returns (bool[] memory res) {
        res = new bool[](marketProxies.length);
        for (uint256 i = 0; i < marketProxies.length; i++) {
            res[i] = marketProxyExists(marketProxies[i]);
        }
    }
}
