// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IDelphiFactory} from "./IDelphiFactory.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DelphiFactory is IDelphiFactory {
    // ========== CONSTANTS ==========
    uint256 internal constant _MIN_MARKET_CREATION_FEE_18 = 0;
    uint256 internal constant _MAX_MARKET_CREATION_FEE_18 = 100e18;

    // ========== IMMUTABLES ==========

    address public immutable override IMPLEMENTATION;
    IERC20Metadata public immutable override TOKEN;
    uint256 public immutable override MARKET_CREATION_FEE;
    uint256 public immutable override MIN_MARKET_CREATION_FEE;
    uint256 public immutable override MAX_MARKET_CREATION_FEE;
    address public immutable override MARKET_CREATION_FEE_RECIPIENT;

    // ========== STATE VARIABLES ==========

    EnumerableSet.AddressSet internal _marketProxies;

    // ========== LIBRARIES ==========
    using EnumerableSet for EnumerableSet.AddressSet;
    using Clones for address;
    using SafeERC20 for IERC20Metadata;

    // ========== CONSTRUCTOR ==========
    constructor(address implementation, uint256 marketCreationFee, address marketCreationFeeRecipient) {
        // Checks: Validate implementation
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }
        if (implementation.code.length == 0) {
            revert ImplementationNotAContract(implementation);
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
            revert MarketCreationFeeTooLow(marketCreationFee, minMarketCreationFee);
        }
        if (marketCreationFee > maxMarketCreationFee) {
            revert MarketCreationFeeTooHigh(marketCreationFee, maxMarketCreationFee);
        }

        // Checks: Validate market creation fee recipient
        if (marketCreationFeeRecipient == address(0)) {
            revert ZeroFeeRecipientAddress();
        }

        // Effects: Set immutables
        IMPLEMENTATION = implementation;
        TOKEN = token;
        MARKET_CREATION_FEE = marketCreationFee;
        MIN_MARKET_CREATION_FEE = minMarketCreationFee;
        MAX_MARKET_CREATION_FEE = maxMarketCreationFee;
        MARKET_CREATION_FEE_RECIPIENT = marketCreationFeeRecipient;
    }

    // ========== FUNCTIONS ==========

    // Permissionless
    function deployNewMarketProxy(
        uint256 initialDeposit_,
        IDelphiMarket.VerifiableUri calldata newMarketMetadata_,
        bytes calldata newMarketInitializationCalldata_
    ) external returns (address newMarketProxy) {
        // Interactions: Deploy new market proxy
        newMarketProxy = IMPLEMENTATION.clone();

        // Interactions: Pull initial deposit into new market proxy
        TOKEN.safeTransferFrom(msg.sender, newMarketProxy, initialDeposit_);

        // Interactions: Initialize new market proxy
        IDelphiMarket(newMarketProxy)
            .initialize({
                marketCreator_: msg.sender,
                initialDeposit_: initialDeposit_,
                newMarketMetadata_: newMarketMetadata_,
                initializationCalldata_: newMarketInitializationCalldata_
            });

        // Effects: Save new market proxy
        _marketProxies.add(newMarketProxy);

        // Effects: Emit event
        emit NewMarketProxy(msg.sender, IMPLEMENTATION, newMarketProxy, newMarketMetadata_);

        // If there is a market creation fee
        if (MARKET_CREATION_FEE > 0) {
            // Interactions: Charge marketCreationFee
            TOKEN.safeTransferFrom(msg.sender, MARKET_CREATION_FEE_RECIPIENT, MARKET_CREATION_FEE);
        }
    }

    // ========== VIEWS ==========

    // Market Proxies
    function getTotalMarketProxiesCount() external view returns (uint256) {
        return _marketProxies.length();
    }

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

    function marketProxyExists(address marketProxy) public view returns (bool) {
        return _marketProxies.contains(marketProxy);
    }

    function marketProxiesExist(address[] calldata marketProxies) external view returns (bool[] memory res) {
        res = new bool[](marketProxies.length);
        for (uint256 i = 0; i < marketProxies.length; i++) {
            res[i] = marketProxyExists(marketProxies[i]);
        }
    }
}
