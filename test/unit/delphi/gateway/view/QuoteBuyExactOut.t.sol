// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LmsrGateway_QuoteBuyExactOut_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using Math for uint256;

    // Tests

    function testFuzz_QuoteBuyExactOut_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Deploy a fresh, uninitialized gateway
        LmsrGateway freshGateway = new LmsrGateway(token, GATEWAY_OWNER);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.GatewayNotInitialized.selector));

        // Quote buy exact out
        freshGateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);
    }

    function testFuzz_QuoteBuyExactOut_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure the fake market proxy is not a real one
        vm.assume(!deployment.factory.marketProxyExists(fakeMarketProxy));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.MarketProxyNotDeployedByFactory.selector, fakeMarketProxy)
        );

        // Quote buy exact out
        deployment.gateway.quoteBuyExactOut(ILmsrMarket(fakeMarketProxy), outcomeIdx, sharesOut);
    }

    function testFuzz_QuoteBuyExactOut_MarketNotOpen_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp past the trading deadline (so the market is no longer OPEN)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.MarketNotOpen.selector));

        // Quote buy exact out
        deployment.gateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);
    }

    function testFuzz_QuoteBuyExactOut_OutcomeIsOutOfBounds_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx out of the configured range
        uint256 outcomeCount = marketProxy.getMarket().config.outcomeCount;
        outcomeIdx = bound(outcomeIdx, outcomeCount, type(uint256).max);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrMarketErrors.OutcomeIsOutOfBounds.selector, outcomeIdx, outcomeCount)
        );

        // Quote buy exact out
        deployment.gateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);
    }

    function testFuzz_QuoteBuyExactOut_SharesOutBelowMinDelta_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out below the minimum delta
        sharesOut = bound(sharesOut, 0, deployment.gateway.MIN_SHARES_DELTA() - 1);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrGatewayErrors.SharesOutBelowMinDelta.selector, sharesOut, deployment.gateway.MIN_SHARES_DELTA()
            )
        );

        // Quote buy exact out
        deployment.gateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);
    }

    function testFuzz_QuoteBuyExactOut_ExpInputTooBig_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out so the exp input overflows (no trades yet, so current supply is zero)
        uint256 b = marketProxy.getMarket().config.b;
        sharesOut = bound(sharesOut, _minSharesOutForExpTooBig(marketProxy, outcomeIdx), type(uint256).max / 1e18);

        // Calculate the expected exp input
        uint256 expInput = sharesOut.mulDiv(1e18, b, Math.Rounding.Floor);
        assertGt(expInput, LmsrMath.MAX_EXP_INPUT, "exp input not big enough");

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrMathErrors.ExpInputTooBig.selector, expInput, LmsrMath.MAX_EXP_INPUT)
        );

        // Quote buy exact out
        deployment.gateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);
    }

    function testFuzz_QuoteBuyExactOut_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out to the valid range
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Quote buy exact out (discarding dust buys below MIN_TOKENS_DELTA)
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        (uint256 tokensIn2,,) = deployment.gateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);

        // Validate (quotes are positive and deterministic)
        assertGt(tokensIn, 0, "tokensIn != positive");
        assertEq(tokensIn, tokensIn2, "quote is not deterministic");
    }
}
