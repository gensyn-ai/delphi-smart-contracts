// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

contract LmsrGateway_TrySweep_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests

    function testFuzz_TrySweep_GatewayNotInitialized_Reverts(
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

        // Try sweep
        freshGateway.trySweep(marketProxy);
    }

    function testFuzz_TrySweep_MarketProxyNotDeployedByFactory_Reverts(
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

        // Try sweep
        deployment.gateway.trySweep(ILmsrMarket(fakeMarketProxy));
    }

    function testFuzz_TrySweep_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address caller
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp past the settlement deadline (so the market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Calculate the full proxy balance (entirely swept to the creator, no trades occurred)
        uint256 proxyBalance = token.balanceOf(address(marketProxy));
        uint256 expectedCreatorTokens = token.balanceOf(MARKET_CREATOR) + proxyBalance;

        // Switch to caller (anyone may call trySweep)
        _useNewSender(caller);

        // Try sweep
        deployment.gateway.trySweep(marketProxy);

        // Validate market state
        assertTrue(marketProxy.losingPayoutSwept(), "losingPayoutSwept != true");
        assertTrue(marketProxy.keeperFeePaid(), "keeperFeePaid != true");
        assertTrue(marketProxy.oracleFeePaid(), "oracleFeePaid != true");
        assertEq(marketProxy.getMarket().pool, 0, "pool != 0");
        assertEq(marketProxy.getMarket().tradingFees, 0, "tradingFees != 0");

        // Validate balances
        assertEq(token.balanceOf(MARKET_CREATOR), expectedCreatorTokens, "creator token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), 0, "market proxy balance != 0");
    }
}
