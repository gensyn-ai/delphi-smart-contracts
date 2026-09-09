// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Mocks
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";

contract LmsrGateway_ResolveMarket_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests

    function testFuzz_ResolveMarket_GatewayNotInitialized_Reverts(
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

        // Resolve market
        freshGateway.resolveMarket(address(marketProxy));
    }

    function testFuzz_ResolveMarket_MarketProxyNotDeployedByFactory_Reverts(
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

        // Resolve market
        deployment.gateway.resolveMarket(fakeMarketProxy);
    }

    // Note: `resolveMarket` reverting with `OracleRelayerNotSet` is unreachable for factory markets —
    // `LmsrMarket.initialize` now requires the gateway to have a relayer wired at creation time, and the
    // relayer can never be reset to address(0). The create-time guard is covered by
    // `DelphiFactory_DeployNewMarketProxy_Test.testFuzz_DeployNewMarketProxy_GatewayOracleRelayerNotSet_Reverts`.

    function testFuzz_ResolveMarket_SettlementAlreadyLocked_Reverts(
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

        // Lock settlement
        _lockSettlement(deployment.gateway, address(marketProxy));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.SettlementAlreadyLocked.selector, address(marketProxy))
        );

        // Resolve market
        deployment.gateway.resolveMarket(address(marketProxy));
    }

    function testFuzz_ResolveMarket_CannotResolveMarketYet_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 warpTime
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp inside the resolve-delay window: trading is closed (AWAITING_SETTLEMENT) but
        // resolution is not allowed yet (window is non-empty since resolveDelay >= MIN_RESOLVE_DELAY)
        ILmsrMarket.MarketConfig memory config = marketProxy.getMarket().config;
        warpTime = bound(warpTime, config.tradingDeadline + 1, config.earliestResolveTime - 1);
        vm.warp(warpTime);

        // Switch to keeper
        _useNewSender(KEEPER);

        // Expect Revert (bubbled up from the market's transferKeeperFee)
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.CannotResolveMarketYet.selector, warpTime, config.earliestResolveTime
            )
        );

        // Resolve market
        deployment.gateway.resolveMarket(address(marketProxy));

        // The whole transaction reverted, so the settlement lock must have been rolled back
        assertFalse(deployment.gateway.settlementLocked(address(marketProxy)), "settlement lock not rolled back");

        // Resolution must still succeed once the resolve delay has elapsed
        oracleRelayer.setOracleFeeRecipient(makeAddr("ORACLE_FEE_RECIPIENT"));
        vm.warp(config.earliestResolveTime);
        deployment.gateway.resolveMarket(address(marketProxy));
        assertTrue(deployment.gateway.settlementLocked(address(marketProxy)), "settlement not locked after delay");
    }

    function testFuzz_ResolveMarket_Success(
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

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Ensure the oracle fee recipient is distinct from the other transfer targets
        vm.assume(oracleFeeRecipient != address(0));
        vm.assume(oracleFeeRecipient != address(marketProxy));
        vm.assume(oracleFeeRecipient != MARKET_CREATOR);
        vm.assume(oracleFeeRecipient != KEEPER);
        vm.assume(oracleFeeRecipient != TRADING_FEES_RECIPIENT);

        // Set outcome and oracle fee recipient on the oracle relayer
        oracleRelayer.setOutcome(address(marketProxy), winningOutcomeIdx);
        oracleRelayer.setOracleFeeRecipient(oracleFeeRecipient);

        // Warp to earliest resolve time
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);

        // Get fees & pool (no trades occurred, so the entire pool is the losing payout swept to the creator)
        uint256 keeperFee = marketProxy.KEEPER_FEE();
        uint256 oracleFee = marketProxy.ORACLE_FEE();
        uint256 pool = marketProxy.getMarket().pool;

        // Record balances
        uint256 expectedKeeperTokens = token.balanceOf(KEEPER) + keeperFee;
        uint256 expectedOracleRecipientTokens = token.balanceOf(oracleFeeRecipient) + oracleFee;
        uint256 expectedCreatorTokens = token.balanceOf(MARKET_CREATOR) + pool;

        // Switch to keeper
        _useNewSender(KEEPER);

        // Expect event emissions
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayMarketSettled(address(marketProxy), winningOutcomeIdx);
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.MarketResolutionRequested(address(marketProxy), KEEPER);

        // Resolve market (drives the full settlement through the mock relayer)
        deployment.gateway.resolveMarket(address(marketProxy));

        // Validate gateway/market state
        assertTrue(deployment.gateway.settlementLocked(address(marketProxy)), "settlement not locked");
        assertTrue(marketProxy.keeperFeePaid(), "keeperFeePaid != true");
        assertTrue(marketProxy.oracleFeePaid(), "oracleFeePaid != true");
        assertEq(marketProxy.getMarket().winningOutcomeIdx, winningOutcomeIdx, "winningOutcomeIdx mismatch");
        assertEq(marketProxy.getMarket().pool, 0, "pool != 0");

        // Validate balances
        assertEq(token.balanceOf(KEEPER), expectedKeeperTokens, "keeper token balance mismatch");
        assertEq(
            token.balanceOf(oracleFeeRecipient), expectedOracleRecipientTokens, "oracle recipient balance mismatch"
        );
        assertEq(token.balanceOf(MARKET_CREATOR), expectedCreatorTokens, "creator token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), 0, "market proxy balance != 0");
    }
}
