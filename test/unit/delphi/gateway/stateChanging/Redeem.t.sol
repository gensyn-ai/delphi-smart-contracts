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

contract LmsrGateway_Redeem_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Functions

    /// @dev Settles the market with `winningOutcomeIdx` through the gateway (assumes the market is AWAITING_SETTLEMENT).
    function _settle(uint256 winningOutcomeIdx) internal {
        _lockSettlement(deployment.gateway, address(marketProxy));
        _useNewSender(address(oracleRelayer));
        deployment.gateway.settleMarket(address(marketProxy), winningOutcomeIdx, MARKET_CREATION_FEE_RECIPIENT);
    }

    // Tests

    function testFuzz_Redeem_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
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

        // Redeem
        freshGateway.redeem(marketProxy);
    }

    function testFuzz_Redeem_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy
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

        // Redeem
        deployment.gateway.redeem(ILmsrMarket(fakeMarketProxy));
    }

    function testFuzz_Redeem_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address redeemer,
        uint256 winningOutcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure redeemer is a clean address
        vm.assume(redeemer != address(0));
        vm.assume(redeemer != address(marketProxy));
        vm.assume(redeemer != MARKET_CREATOR);
        vm.assume(redeemer != MARKET_CREATION_FEE_RECIPIENT);

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out (must be at least the token decimal scaler, so the redeemer reward is positive)
        uint256 minShares = deployment.gateway.MIN_SHARES_DELTA();
        if (marketProxy.TOKEN_DECIMAL_SCALER() > minShares) {
            minShares = marketProxy.TOKEN_DECIMAL_SCALER();
        }
        sharesOut =
            bound(sharesOut, minShares, _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: winningOutcomeIdx}));

        // Buy winning shares for the redeemer
        _buyViaGateway({
            buyer: redeemer,
            gateway: deployment.gateway,
            marketProxy: marketProxy,
            token: token,
            outcomeIdx: winningOutcomeIdx,
            sharesOut: sharesOut
        });

        // Warp into the settlement window (so the market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Settle the market (so it is SETTLED)
        _settle(winningOutcomeIdx);

        // Get redeemer winning shares
        uint256 winningSharesIn = marketProxy.balanceOf(redeemer, winningOutcomeIdx);

        // Calculate expected tokens out (rounded down against the user)
        uint256 expectedTokensOut = winningSharesIn / marketProxy.TOKEN_DECIMAL_SCALER();

        // Record balances
        uint256 expectedRedeemerTokens = token.balanceOf(redeemer) + expectedTokensOut;
        uint256 expectedMarketTokens = token.balanceOf(address(marketProxy)) - expectedTokensOut;
        uint256 expectedMarketPool = marketProxy.getMarket().pool - expectedTokensOut;
        uint256 expectedMarketShares = marketProxy.balanceOf(address(marketProxy), winningOutcomeIdx) + winningSharesIn;

        // Switch to redeemer
        _useNewSender(redeemer);

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayRedemption(marketProxy, redeemer, winningSharesIn, expectedTokensOut);

        // Redeem
        (uint256 sharesIn, uint256 tokensOut) = deployment.gateway.redeem(marketProxy);

        // Validate return values
        assertEq(sharesIn, winningSharesIn, "sharesIn != winningSharesIn");
        assertEq(tokensOut, expectedTokensOut, "tokensOut != expectedTokensOut");

        // Validate balances
        assertEq(token.balanceOf(redeemer), expectedRedeemerTokens, "redeemer token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), expectedMarketTokens, "market token balance mismatch");
        assertEq(marketProxy.getMarket().pool, expectedMarketPool, "market pool mismatch");

        // Validate shares (pulled from redeemer to the market)
        assertEq(marketProxy.balanceOf(redeemer, winningOutcomeIdx), 0, "redeemer shares not pulled");
        assertEq(
            marketProxy.balanceOf(address(marketProxy), winningOutcomeIdx),
            expectedMarketShares,
            "market shares mismatch"
        );
    }
}
