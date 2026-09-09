// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";

// Mocks
import {MockToken} from "test/support/mocks/MockToken.sol";

// Interfaces
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";

contract LmsrMarket_Constructor_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    LmsrGateway gateway;
    LmsrMarket implementation;

    // Functions

    /// @dev Deploys a fresh token + gateway + reference implementation (used only to read the constants).
    function _deployTokenAndGateway(uint8 tokenDecimals) internal {
        token = new MockToken({
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            _decimals: _boundUint8(tokenDecimals, 6, 18),
            admin: TOKEN_ADMIN,
            initialAmount: 0
        });
        gateway = new LmsrGateway(token, GATEWAY_OWNER);
        implementation = new LmsrMarket({
            tradingFeesRecipient: TRADING_FEES_RECIPIENT,
            gateway: address(gateway),
            tradingFeesRecipientPct: 0,
            keeperFee: 0,
            oracleFee: 0
        });
    }

    // Tests

    function testFuzz_TradingFeesRecipientIsZeroAddress_Reverts(
        uint8 tokenDecimals,
        uint256 tradingFeesRecipientPct,
        uint256 keeperFee,
        uint256 oracleFee
    ) external {
        // Deploy token and gateway
        _deployTokenAndGateway(tokenDecimals);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.TradingFeesRecipientIsZeroAddress.selector));

        // Deploy market with a zero trading fees recipient
        new LmsrMarket({
            tradingFeesRecipient: address(0),
            gateway: address(gateway),
            tradingFeesRecipientPct: tradingFeesRecipientPct,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });
    }

    function testFuzz_GatewayIsZeroAddress_Reverts(
        uint8 tokenDecimals,
        address tradingFeesRecipient,
        uint256 tradingFeesRecipientPct,
        uint256 keeperFee,
        uint256 oracleFee
    ) external {
        // Deploy token and gateway
        _deployTokenAndGateway(tokenDecimals);

        // Ensure trading fees recipient is not zero address
        vm.assume(tradingFeesRecipient != address(0));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.GatewayIsZeroAddress.selector));

        // Deploy market with a zero gateway
        new LmsrMarket({
            tradingFeesRecipient: tradingFeesRecipient,
            gateway: address(0),
            tradingFeesRecipientPct: tradingFeesRecipientPct,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });
    }

    // Note: TradingFeesRecipientPctIsTooLow is unreachable: MIN_TRADING_FEES_RECIPIENT_PCT is 0 and
    //       tradingFeesRecipientPct is a uint256, so `tradingFeesRecipientPct < 0` can never be true.

    function testFuzz_TradingFeesRecipientPctIsTooHigh_Reverts(
        uint8 tokenDecimals,
        address tradingFeesRecipient,
        uint256 tradingFeesRecipientPct,
        uint256 keeperFee,
        uint256 oracleFee
    ) external {
        // Deploy token and gateway
        _deployTokenAndGateway(tokenDecimals);

        // Ensure trading fees recipient is not zero address
        vm.assume(tradingFeesRecipient != address(0));

        // Set trading fees recipient pct too high
        tradingFeesRecipientPct =
            bound(tradingFeesRecipientPct, implementation.MAX_TRADING_FEES_RECIPIENT_PCT() + 1, type(uint256).max);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.TradingFeesRecipientPctIsTooHigh.selector,
                tradingFeesRecipientPct,
                implementation.MAX_TRADING_FEES_RECIPIENT_PCT()
            )
        );

        // Deploy market with a too high trading fees recipient pct
        new LmsrMarket({
            tradingFeesRecipient: tradingFeesRecipient,
            gateway: address(gateway),
            tradingFeesRecipientPct: tradingFeesRecipientPct,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });
    }

    function testFuzz_Constructor_Success(
        uint8 tokenDecimals,
        address tradingFeesRecipient,
        uint256 tradingFeesRecipientPct,
        uint256 keeperFee,
        uint256 oracleFee,
        ILmsrMarketTypes.MarketConfig memory marketConfig
    ) external {
        // Deploy token and gateway
        _deployTokenAndGateway(tokenDecimals);

        // Ensure trading fees recipient is not zero address
        vm.assume(tradingFeesRecipient != address(0));

        // Bound trading fees recipient pct
        tradingFeesRecipientPct = bound(
            tradingFeesRecipientPct,
            implementation.MIN_TRADING_FEES_RECIPIENT_PCT(),
            implementation.MAX_TRADING_FEES_RECIPIENT_PCT()
        );

        // Deploy market
        LmsrMarket market = new LmsrMarket({
            tradingFeesRecipient: tradingFeesRecipient,
            gateway: address(gateway),
            tradingFeesRecipientPct: tradingFeesRecipientPct,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });

        // Validate immutables
        assertEq(market.TRADING_FEES_RECIPIENT(), tradingFeesRecipient, "TRADING_FEES_RECIPIENT mismatch");
        assertEq(market.GATEWAY(), address(gateway), "GATEWAY mismatch");
        assertEq(market.TRADING_FEES_RECIPIENT_PCT(), tradingFeesRecipientPct, "TRADING_FEES_RECIPIENT_PCT mismatch");
        assertEq(market.KEEPER_FEE(), keeperFee, "KEEPER_FEE mismatch");
        assertEq(market.ORACLE_FEE(), oracleFee, "ORACLE_FEE mismatch");
        assertEq(address(market.TOKEN()), address(gateway.TOKEN()), "TOKEN mismatch");
        assertEq(market.TOKEN_DECIMAL_SCALER(), gateway.TOKEN_DECIMAL_SCALER(), "TOKEN_DECIMAL_SCALER mismatch");

        // Validate initializers are disabled on the implementation
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        market.initialize({
            marketCreator_: tradingFeesRecipient,
            newMarketConfig_: marketConfig,
            newMarketMetadata_: _dummyVerifiableUri()
        });
    }
}
