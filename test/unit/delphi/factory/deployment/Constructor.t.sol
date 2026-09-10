// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {DelphiFactory} from "src/factory/DelphiFactory.sol";
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";

// Mocks
import {MockToken} from "test/support/mocks/MockToken.sol";

// Interfaces
import {IDelphiFactoryErrors} from "src/factory/IDelphiFactoryErrors.sol";

contract DelphiFactory_Constructor_Test is DelphiTestUtils {
    // Functions

    /// @dev Deploys a fresh token + gateway + market implementation with the given settlement fees.
    function _deployImplementation(uint8 tokenDecimals, uint256 keeperFee, uint256 oracleFee)
        internal
        returns (LmsrMarket implementation)
    {
        // Deploy Token
        MockToken token = new MockToken({
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            _decimals: _boundUint8(tokenDecimals, 6, 18),
            admin: TOKEN_ADMIN,
            initialAmount: 0
        });

        // Deploy Gateway
        LmsrGateway gateway = new LmsrGateway(token, GATEWAY_OWNER);

        // Deploy & Return Implementation
        implementation = new LmsrMarket({
            tradingFeesRecipient: TRADING_FEES_RECIPIENT,
            gateway: address(gateway),
            tradingFeesRecipientPct: 0,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });
    }

    // ===== IMPLEMENTATION =====

    function testFuzz_Constructor_ImplementationIsZeroAddress_Reverts(
        uint256 marketCreationFee,
        address marketCreationFeeRecipient
    ) external {
        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(IDelphiFactoryErrors.ImplementationIsZeroAddress.selector));

        // Deploy factory with a zero implementation
        new DelphiFactory({
            implementation: address(0),
            marketCreationFee: marketCreationFee,
            marketCreationFeeRecipient: marketCreationFeeRecipient
        });
    }

    function testFuzz_Constructor_ImplementationIsNotAContract_Reverts(
        address implementation_,
        uint256 marketCreationFee,
        address marketCreationFeeRecipient
    ) external {
        // Ensure implementation is a non-zero, non-contract address
        vm.assume(implementation_ != address(0));
        vm.assume(implementation_.code.length == 0);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(IDelphiFactoryErrors.ImplementationIsNotAContract.selector, implementation_)
        );

        // Deploy factory with a non-contract implementation
        new DelphiFactory({
            implementation: implementation_,
            marketCreationFee: marketCreationFee,
            marketCreationFeeRecipient: marketCreationFeeRecipient
        });
    }

    // ===== MARKET CREATION FEE =====

    // Note: MarketCreationFeeIsTooLow is unreachable: the minimum market creation fee is 0 and the fee is a
    //       uint256, so `marketCreationFee < 0` can never be true.

    function testFuzz_Constructor_MarketCreationFeeIsTooHigh_Reverts(
        uint8 tokenDecimals,
        uint256 marketCreationFee,
        address marketCreationFeeRecipient
    ) external {
        // Deploy implementation
        LmsrMarket implementation_ = _deployImplementation(tokenDecimals, 0, 0);

        // Calculate the max market creation fee
        uint256 maxMarketCreationFee = 100e18 / implementation_.TOKEN_DECIMAL_SCALER();

        // Set the market creation fee too high
        marketCreationFee = bound(marketCreationFee, maxMarketCreationFee + 1, type(uint256).max);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDelphiFactoryErrors.MarketCreationFeeIsTooHigh.selector, marketCreationFee, maxMarketCreationFee
            )
        );

        // Deploy factory with a too high market creation fee
        new DelphiFactory({
            implementation: address(implementation_),
            marketCreationFee: marketCreationFee,
            marketCreationFeeRecipient: marketCreationFeeRecipient
        });
    }

    // ===== MARKET CREATION FEE RECIPIENT =====

    function testFuzz_Constructor_MarketCreationFeeRecipientIsZeroAddress_Reverts(uint8 tokenDecimals) external {
        // Deploy implementation (no settlement fees, so the settlement check is not hit)
        LmsrMarket implementation_ = _deployImplementation(tokenDecimals, 0, 0);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(IDelphiFactoryErrors.MarketCreationFeeRecipientIsZeroAddress.selector));

        // Deploy factory with a zero market creation fee recipient
        new DelphiFactory({
            implementation: address(implementation_), marketCreationFee: 0, marketCreationFeeRecipient: address(0)
        });
    }

    // ===== SETTLEMENT FEES =====

    function testFuzz_Constructor_SettlementFeesExceedMarketCreationFee_Reverts(
        uint8 tokenDecimals,
        uint256 keeperFee,
        uint256 oracleFee,
        uint256 marketCreationFee,
        address marketCreationFeeRecipient
    ) external {
        // Ensure recipient is not the zero address (so we reach the settlement fees check)
        vm.assume(marketCreationFeeRecipient != address(0));

        // Bound decimals & calculate the max market creation fee
        tokenDecimals = _boundUint8(tokenDecimals, 6, 18);
        uint256 maxMarketCreationFee = 100e18 / (10 ** (18 - tokenDecimals));

        // Bound settlement fees to [1, maxMarketCreationFee]
        keeperFee = bound(keeperFee, 1, maxMarketCreationFee);
        oracleFee = bound(oracleFee, 0, maxMarketCreationFee - keeperFee);
        uint256 settlementFees = keeperFee + oracleFee;

        // Deploy implementation with the settlement fees
        LmsrMarket implementation_ = _deployImplementation(tokenDecimals, keeperFee, oracleFee);

        // Set the market creation fee below the settlement fees
        marketCreationFee = bound(marketCreationFee, 0, settlementFees - 1);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IDelphiFactoryErrors.SettlementFeesExceedMarketCreationFee.selector, settlementFees, marketCreationFee
            )
        );

        // Deploy factory
        new DelphiFactory({
            implementation: address(implementation_),
            marketCreationFee: marketCreationFee,
            marketCreationFeeRecipient: marketCreationFeeRecipient
        });
    }

    // ===== SUCCESS =====

    function testFuzz_Constructor_Success(
        uint8 tokenDecimals,
        uint256 keeperFee,
        uint256 oracleFee,
        uint256 marketCreationFee,
        address marketCreationFeeRecipient
    ) external {
        // Ensure recipient is not the zero address
        vm.assume(marketCreationFeeRecipient != address(0));

        // Bound decimals & calculate the max market creation fee
        tokenDecimals = _boundUint8(tokenDecimals, 6, 18);
        uint256 maxMarketCreationFee = 100e18 / (10 ** (18 - tokenDecimals));

        // Bound settlement fees to [0, maxMarketCreationFee]
        keeperFee = bound(keeperFee, 0, maxMarketCreationFee);
        oracleFee = bound(oracleFee, 0, maxMarketCreationFee - keeperFee);
        uint256 settlementFees = keeperFee + oracleFee;

        // Deploy implementation with the settlement fees
        LmsrMarket implementation_ = _deployImplementation(tokenDecimals, keeperFee, oracleFee);

        // Set the market creation fee at least the settlement fees, at most the max
        marketCreationFee = bound(marketCreationFee, settlementFees, maxMarketCreationFee);

        // Deploy factory
        DelphiFactory factory_ = new DelphiFactory({
            implementation: address(implementation_),
            marketCreationFee: marketCreationFee,
            marketCreationFeeRecipient: marketCreationFeeRecipient
        });

        // Validate immutables
        assertEq(factory_.IMPLEMENTATION(), address(implementation_), "IMPLEMENTATION mismatch");
        assertEq(address(factory_.TOKEN()), address(implementation_.TOKEN()), "TOKEN mismatch");
        assertEq(factory_.MARKET_CREATION_FEE(), marketCreationFee, "MARKET_CREATION_FEE mismatch");
        assertEq(factory_.SETTLEMENT_FEES(), settlementFees, "SETTLEMENT_FEES mismatch");
        assertEq(
            factory_.MARKET_CREATION_FEE_RECIPIENT(),
            marketCreationFeeRecipient,
            "MARKET_CREATION_FEE_RECIPIENT mismatch"
        );
    }
}
