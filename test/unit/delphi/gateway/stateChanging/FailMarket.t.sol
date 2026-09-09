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

contract LmsrGateway_FailMarket_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests

    function testFuzz_FailMarket_CallerIsNotOracleRelayer_Reverts(
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

        // Ensure caller is not the oracle relayer
        vm.assume(caller != address(oracleRelayer));

        // Switch to caller
        _useNewSender(caller);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.CallerIsNotOracleRelayer.selector, caller));

        // Fail market
        deployment.gateway.failMarket(address(marketProxy));
    }

    function testFuzz_FailMarket_GatewayNotInitialized_Reverts(
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

        // Deploy a fresh, uninitialized gateway and set its oracle relayer
        LmsrGateway freshGateway = new LmsrGateway(token, GATEWAY_OWNER);
        _useNewSender(GATEWAY_OWNER);
        freshGateway.setOracleRelayer(address(oracleRelayer));

        // Switch to the oracle relayer
        _useNewSender(address(oracleRelayer));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.GatewayNotInitialized.selector));

        // Fail market
        freshGateway.failMarket(address(marketProxy));
    }

    function testFuzz_FailMarket_MarketProxyNotDeployedByFactory_Reverts(
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

        // Switch to the oracle relayer
        _useNewSender(address(oracleRelayer));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.MarketProxyNotDeployedByFactory.selector, fakeMarketProxy)
        );

        // Fail market
        deployment.gateway.failMarket(fakeMarketProxy);
    }

    function testFuzz_FailMarket_SettlementNotLocked_Reverts(
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

        // Switch to the oracle relayer (settlement is not locked — resolveMarket was never called)
        _useNewSender(address(oracleRelayer));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.SettlementNotLocked.selector));

        // Fail market
        deployment.gateway.failMarket(address(marketProxy));
    }

    function testFuzz_FailMarket_Success(
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

        // Lock settlement (normally done by resolveMarket) — failMarket now requires the lock
        _lockSettlement(deployment.gateway, address(marketProxy));

        // Warp into the settlement window (so the market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Note: fail no longer calls trySweep
        // // Calculate the full proxy balance (entirely swept to the creator, no trades occurred)
        // uint256 proxyBalance = token.balanceOf(address(marketProxy));
        // uint256 expectedCreatorTokens = token.balanceOf(MARKET_CREATOR) + proxyBalance;

        // Switch to the oracle relayer
        _useNewSender(address(oracleRelayer));

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayMarketFailed(address(marketProxy));

        // Fail market
        deployment.gateway.failMarket(address(marketProxy));

        // Validate market state
        assertTrue(marketProxy.marketFailed(), "marketFailed != true");
    }
}
