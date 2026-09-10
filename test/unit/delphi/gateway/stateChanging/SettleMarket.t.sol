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

contract LmsrGateway_SettleMarket_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests

    function testFuzz_SettleMarket_CallerIsNotOracleRelayer_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address caller,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient
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

        // Settle market
        deployment.gateway.settleMarket(address(marketProxy), winningOutcomeIdx, oracleFeeRecipient);
    }

    function testFuzz_SettleMarket_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient
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

        // Switch to the oracle relayer (so the onlyOracleRelayer check passes)
        _useNewSender(address(oracleRelayer));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.GatewayNotInitialized.selector));

        // Settle market
        freshGateway.settleMarket(address(marketProxy), winningOutcomeIdx, oracleFeeRecipient);
    }

    function testFuzz_SettleMarket_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient
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

        // Settle market
        deployment.gateway.settleMarket(fakeMarketProxy, winningOutcomeIdx, oracleFeeRecipient);
    }

    function testFuzz_SettleMarket_SettlementNotLocked_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Switch to the oracle relayer (settlement is not locked)
        _useNewSender(address(oracleRelayer));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.SettlementNotLocked.selector));

        // Settle market
        deployment.gateway.settleMarket(address(marketProxy), winningOutcomeIdx, oracleFeeRecipient);
    }

    function testFuzz_SettleMarket_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient,
        bool marketCreatorBlacklisted
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Ensure the oracle fee recipient is distinct from the other transfer targets
        vm.assume(oracleFeeRecipient != address(0));
        vm.assume(oracleFeeRecipient != address(marketProxy));
        vm.assume(oracleFeeRecipient != MARKET_CREATOR);
        vm.assume(oracleFeeRecipient != TRADING_FEES_RECIPIENT);

        // Lock settlement (normally done by resolveMarket)
        _lockSettlement(deployment.gateway, address(marketProxy));

        // Warp into the settlement window (so the market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Get fees & pool
        uint256 oracleFee = marketProxy.ORACLE_FEE();
        uint256 pool = marketProxy.getMarket().pool;

        // Record balances
        uint256 expectedOracleRecipientTokens = token.balanceOf(oracleFeeRecipient) + oracleFee;
        uint256 expectedCreatorTokens;

        // Blacklist market creator (if specified)
        if (marketCreatorBlacklisted) {
            // Switch to token admin
            _useNewSender(token.ADMIN());

            // Blacklist market creator
            token.blacklist(MARKET_CREATOR);

            // Set expected creator tokens
            expectedCreatorTokens = token.balanceOf(MARKET_CREATOR);
        } else {
            // Set expected creator tokens
            expectedCreatorTokens = token.balanceOf(MARKET_CREATOR) + pool;
        }

        // Switch to the oracle relayer
        _useNewSender(address(oracleRelayer));

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayMarketSettled(address(marketProxy), winningOutcomeIdx);

        // Settle market
        (uint256 losingPayout, uint256 tradingFeesRecipientCut, uint256 marketCreatorTradingFeesCut) =
            deployment.gateway.settleMarket(address(marketProxy), winningOutcomeIdx, oracleFeeRecipient);

        // Validate return values (no trades occurred, so all fees are zero and the entire pool is the losing payout)
        assertEq(losingPayout, pool, "losingPayout != pool");
        assertEq(tradingFeesRecipientCut, 0, "tradingFeesRecipientCut != 0");
        assertEq(marketCreatorTradingFeesCut, 0, "marketCreatorTradingFeesCut != 0");

        // Validate market state
        assertEq(marketProxy.getMarket().winningOutcomeIdx, winningOutcomeIdx, "winningOutcomeIdx mismatch");
        assertEq(marketProxy.getMarket().pool, 0, "pool != 0");
        assertTrue(marketProxy.oracleFeePaid(), "oracleFeePaid != true");

        // The settlement lock is permanent — it stays true after settle (guards against re-settlement)
        assertTrue(deployment.gateway.settlementLocked(address(marketProxy)), "settlement lock should remain true");

        // Validate balances
        assertEq(
            token.balanceOf(oracleFeeRecipient), expectedOracleRecipientTokens, "oracle recipient balance mismatch"
        );
        assertEq(token.balanceOf(MARKET_CREATOR), expectedCreatorTokens, "creator token balance mismatch");
    }
}
