// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LmsrGateway_Liquidate_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;
    using Math for uint256;

    // Tests

    function testFuzz_Liquidate_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256[] calldata outcomeIndices
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

        // Liquidate
        freshGateway.liquidate(marketProxy, outcomeIndices);
    }

    function testFuzz_Liquidate_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        uint256[] calldata outcomeIndices
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

        // Liquidate
        deployment.gateway.liquidate(ILmsrMarket(fakeMarketProxy), outcomeIndices);
    }

    // Note: To solve stack depth issues
    struct LiquidateArgs {
        address liquidator;
        uint256 outcomeIdx;
        uint256 sharesOut;
    }

    // Note: To solve stack depth issues
    struct LiquidateExpectations {
        uint256 sharesIn;
        uint256 totalTokensOut;
        uint256 liquidatorOutcomeSharesAfter;
        uint256 marketOutcomeSharesAfter;
        uint256 marketPoolAfter;
        uint256 liquidatorTokensAfter;
        uint256 marketTokensAfter;
    }

    function testFuzz_Liquidate_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        LiquidateArgs memory args
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure liquidator is not the zero address
        vm.assume(args.liquidator != address(0));
        vm.assume(args.liquidator != marketProxy.marketCreator());
        vm.assume(args.liquidator != deployment.implementation.TRADING_FEES_RECIPIENT());

        // Bound outcome idx
        args.outcomeIdx = bound(args.outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        args.sharesOut = bound(
            args.sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: args.outcomeIdx})
        );

        // Buy shares for the liquidator
        _buyViaGateway({
            buyer: args.liquidator,
            gateway: deployment.gateway,
            marketProxy: marketProxy,
            token: token,
            outcomeIdx: args.outcomeIdx,
            sharesOut: args.sharesOut
        });

        // Warp past the settlement deadline (so the market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Calculate expectations
        LiquidateExpectations memory expectations = _buildExpectations(args.liquidator, args.outcomeIdx);

        // Build outcome indices array (for liquidate call)
        uint256[] memory outcomeIndices = new uint256[](1);
        outcomeIndices[0] = args.outcomeIdx;

        // Build expected shares in array (for event emission)
        uint256[] memory expectedSharesIn = new uint256[](1);
        expectedSharesIn[0] = expectations.sharesIn;

        // Switch to liquidator
        _useNewSender(args.liquidator);

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayLiquidation(
            marketProxy, args.liquidator, outcomeIndices, expectedSharesIn, expectations.totalTokensOut
        );

        // Liquidate
        (uint256[] memory sharesIn, uint256 totalTokensOut) = deployment.gateway.liquidate(marketProxy, outcomeIndices);

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Validate expectations
        assertEq(sharesIn[0], expectations.sharesIn, "unxpected shares in");
        assertEq(totalTokensOut, expectations.totalTokensOut, "totalTokensOut mismatch");
        assertEq(
            marketProxy.balanceOf(args.liquidator, args.outcomeIdx),
            expectations.liquidatorOutcomeSharesAfter,
            "liquidator outcome shares mismatch"
        );
        assertEq(
            marketProxy.balanceOf(address(marketProxy), args.outcomeIdx),
            expectations.marketOutcomeSharesAfter,
            "market outcome shares mismatch"
        );
        assertEq(market.pool, expectations.marketPoolAfter, "market pool mismatch");
        assertEq(token.balanceOf(args.liquidator), expectations.liquidatorTokensAfter, "liquidator tokens mismatch");
        assertEq(token.balanceOf(address(marketProxy)), expectations.marketTokensAfter, "market tokens mismatch");
    }

    function _buildExpectations(address liquidator, uint256 outcomeIdx)
        internal
        view
        returns (LiquidateExpectations memory expectations)
    {
        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get liquidator shares
        uint256 liquidatorShares = marketProxy.balanceOf(liquidator, outcomeIdx);

        // Get outcome supply
        uint256 outcomeSupply = marketProxy.totalSupply(outcomeIdx);

        // Calculate outcome exp
        uint256 outcomeExp = LmsrMath.outcomeExp(market.config.b, outcomeSupply);

        // Calculate numerator sum 36
        uint256 numeratorSum36 = liquidatorShares * outcomeExp;

        // Calculate expected total tokens out
        uint256 expectedTotalTokensOut = numeratorSum36.liquidatorTotalReward({
            currentExpSum: market.expSum, tokenDecimalScaler: deployment.implementation.TOKEN_DECIMAL_SCALER()
        });

        // Return expectations
        return LiquidateExpectations({
            sharesIn: liquidatorShares,
            totalTokensOut: expectedTotalTokensOut,
            liquidatorOutcomeSharesAfter: 0,
            marketOutcomeSharesAfter: marketProxy.balanceOf(address(marketProxy), outcomeIdx) + liquidatorShares,
            marketPoolAfter: 0,
            liquidatorTokensAfter: token.balanceOf(liquidator) + expectedTotalTokensOut,
            marketTokensAfter: 0
        });
    }
}
