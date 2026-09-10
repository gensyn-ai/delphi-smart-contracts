// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract LmsrMarket_TrySweep_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Functions

    /// @dev Buys `sharesOut` of `outcomeIdx` for `buyer` (called while the market is OPEN, pranked as gateway).
    function _buy(address buyer, uint256 outcomeIdx, uint256 sharesOut) internal {
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        _useNewSender(buyer);
        deal(address(token), buyer, tokensIn);
        token.approve(address(marketProxy), tokensIn);

        _useNewSender(address(deployment.gateway));
        marketProxy.buy({buyer: buyer, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});
    }

    // Tests

    function testFuzz_TrySweep_CallerIsNotGateway_Reverts(
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

        // Switch to caller
        _useNewSender(caller);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.CallerIsNotGateway.selector, caller));

        // Try sweep
        marketProxy.trySweep();
    }

    function testFuzz_TrySweep_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address buyer,
        uint256 outcomeIdx,
        uint256 sharesOut,
        bool marketCreatorBlacklisted
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure buyer is a clean address distinct from the fee recipients
        vm.assume(buyer != address(0));
        vm.assume(buyer != address(marketProxy));
        vm.assume(buyer != marketProxy.marketCreator());
        vm.assume(buyer != marketProxy.TRADING_FEES_RECIPIENT());

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Buy shares (generates trading fees and grows the pool)
        _buy({buyer: buyer, outcomeIdx: outcomeIdx, sharesOut: sharesOut});

        // Warp past the settlement deadline (so market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Calculate expectations
        uint256 totalLiquidationPayout = _totalLiquidationPayout(market);
        uint256 tradingFeesRecipientCut = market.tradingFees
            .tradingFeesRecipientCut({tradingFeesRecipientPct: marketProxy.TRADING_FEES_RECIPIENT_PCT()});
        uint256 marketCreatorTradingFeesCut = market.tradingFees - tradingFeesRecipientCut;
        uint256 remainingPayout = market.pool - totalLiquidationPayout;
        uint256 marketCreatorSweepAmount =
            marketCreatorTradingFeesCut + remainingPayout + marketProxy.KEEPER_FEE() + marketProxy.ORACLE_FEE();

        // Record balances
        uint256 expectedTradingFeesRecipientTokens =
            token.balanceOf(marketProxy.TRADING_FEES_RECIPIENT()) + tradingFeesRecipientCut;
        uint256 expectedMarketCreatorTokens = token.balanceOf(marketProxy.marketCreator());
        uint256 expectedMarketTokens = totalLiquidationPayout;
        uint256 expectedMarketCreatorClaimable = 0;

        // Blacklist market creator (if specified)
        if (marketCreatorBlacklisted) {
            // Switch to token admin
            _useNewSender(token.ADMIN());

            // Blacklist market creator
            token.blacklist(MARKET_CREATOR);

            // The sweep amount stays in the market as a claimable balance
            expectedMarketTokens += marketCreatorSweepAmount;
            expectedMarketCreatorClaimable = marketCreatorSweepAmount;

            // Switch back to gateway (trySweep is onlyGateway)
            _useNewSender(address(deployment.gateway));
        } else {
            expectedMarketCreatorTokens += marketCreatorSweepAmount;
        }

        // Try sweep
        marketProxy.trySweep();

        // Refresh market
        market = marketProxy.getMarket();

        // Validate state
        assertEq(market.tradingFees, 0, "tradingFees != 0");
        assertEq(market.pool, totalLiquidationPayout, "pool != totalLiquidationPayout");
        assertTrue(marketProxy.losingPayoutSwept(), "losingPayoutSwept != true");
        assertTrue(marketProxy.keeperFeePaid(), "keeperFeePaid != true");
        assertTrue(marketProxy.oracleFeePaid(), "oracleFeePaid != true");
        assertEq(
            marketProxy.marketCreatorClaimable(), expectedMarketCreatorClaimable, "marketCreatorClaimable mismatch"
        );

        // Validate balances
        assertEq(token.balanceOf(address(marketProxy)), expectedMarketTokens, "market token balance mismatch");
        assertEq(
            token.balanceOf(marketProxy.TRADING_FEES_RECIPIENT()),
            expectedTradingFeesRecipientTokens,
            "trading fees recipient token balance mismatch"
        );
        assertEq(
            token.balanceOf(marketProxy.marketCreator()),
            expectedMarketCreatorTokens,
            "market creator token balance mismatch"
        );
    }

    /// @dev The keeper fee left the proxy when `resolveMarket` ran, so a later sweep of the
    ///      expired market (the oracle never responded) must NOT re-credit it to the creator.
    function testFuzz_TrySweep_ExpiredResolvedMarket_DoesNotSweepKeeperFee(
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

        // Warp to earliest resolve time (so market is AWAITING_SETTLEMENT and resolvable)
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);

        // Make the relayer lock-only (it receives the resolution request but never responds)
        oracleRelayer.setLockOnly(true);

        // Switch to keeper
        _useNewSender(KEEPER);

        // Resolve market (pays the keeper fee out of the proxy; the market stays AWAITING_SETTLEMENT)
        deployment.gateway.resolveMarket(address(marketProxy));

        // Validate the keeper fee was paid
        assertTrue(marketProxy.keeperFeePaid(), "keeperFeePaid != true");
        assertEq(token.balanceOf(KEEPER), marketProxy.KEEPER_FEE(), "keeper token balance != KEEPER_FEE");

        // Warp past the settlement deadline (so market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Calculate expectations (no trades occurred, so the whole pool plus the unpaid oracle fee
        // sweeps to the creator — but NOT the already-paid keeper fee)
        uint256 expectedCreatorTokens =
            token.balanceOf(MARKET_CREATOR) + marketProxy.getMarket().pool + marketProxy.ORACLE_FEE();

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Try sweep
        marketProxy.trySweep();

        // Validate
        assertEq(token.balanceOf(MARKET_CREATOR), expectedCreatorTokens, "market creator token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), 0, "market token balance != 0");
        assertEq(marketProxy.marketCreatorClaimable(), 0, "marketCreatorClaimable != 0");
        assertEq(token.balanceOf(KEEPER), marketProxy.KEEPER_FEE(), "keeper token balance changed");
    }

    function testFuzz_TrySweep_ExpiredMarket_MarketCreatorUnblacklisted_ClaimsRewards(
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

        // Warp past the settlement deadline (so market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Switch to token admin
        _useNewSender(token.ADMIN());

        // Blacklist market creator
        token.blacklist(MARKET_CREATOR);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Try sweep (the market creator reward transfer fails, so it accrues as claimable)
        marketProxy.trySweep();

        // Validate the rewards accrued as claimable and the market creator received nothing
        uint256 claimable = marketProxy.marketCreatorClaimable();
        assertGt(claimable, 0, "marketCreatorClaimable should be > 0");
        assertEq(token.balanceOf(MARKET_CREATOR), 0, "market creator token balance != 0");

        // Switch to token admin
        _useNewSender(token.ADMIN());

        // Unblacklist market creator
        token.unblacklist(MARKET_CREATOR);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(marketProxy));
        emit ILmsrMarket.MarketCreatorRewardTransferred(claimable);

        // Try sweep again (now the claimable rewards get transferred)
        marketProxy.trySweep();

        // Validate
        assertEq(token.balanceOf(MARKET_CREATOR), claimable, "market creator token balance != claimable");
        assertEq(marketProxy.marketCreatorClaimable(), 0, "marketCreatorClaimable != 0");
    }

    function testFuzz_TrySweep_SettledMarket_MarketCreatorUnblacklisted_ClaimsRewards(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Skip time, so market is AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Switch to token admin
        _useNewSender(token.ADMIN());

        // Blacklist market creator
        token.blacklist(MARKET_CREATOR);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Settle market (the market creator reward transfer fails, so it accrues as claimable)
        marketProxy.settleMarket({
            winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: makeAddr("ORACLE_FEE_RECIPIENT")
        });

        // Validate the rewards accrued as claimable and the market creator received nothing
        uint256 claimable = marketProxy.marketCreatorClaimable();
        assertGt(claimable, 0, "marketCreatorClaimable should be > 0");
        assertEq(token.balanceOf(MARKET_CREATOR), 0, "market creator token balance != 0");
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.SETTLED), "market status != SETTLED"
        );

        // Switch to token admin
        _useNewSender(token.ADMIN());

        // Unblacklist market creator
        token.unblacklist(MARKET_CREATOR);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(marketProxy));
        emit ILmsrMarket.MarketCreatorRewardTransferred(claimable);

        // Try sweep (a SETTLED market only transfers the claimable rewards)
        marketProxy.trySweep();

        // Validate
        assertEq(token.balanceOf(MARKET_CREATOR), claimable, "market creator token balance != claimable");
        assertEq(marketProxy.marketCreatorClaimable(), 0, "marketCreatorClaimable != 0");
    }

    function _totalLiquidationPayout(ILmsrMarket.Market memory market) internal view returns (uint256) {
        // Initialize numerator sum
        uint256 numeratorSum36;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < market.config.outcomeCount; outcomeIdx++) {
            // Get outcome total supply
            uint256 outcomeTotalSupply = marketProxy.totalSupply(outcomeIdx);

            // Get outcome external supply
            uint256 outcomeExternalSupply = outcomeTotalSupply - marketProxy.balanceOf(address(marketProxy), outcomeIdx);

            // Calculate outcome exp
            uint256 outcomeExp = LmsrMath.outcomeExp(market.config.b, outcomeTotalSupply);

            // Add to numerator sum
            numeratorSum36 += outcomeExternalSupply * outcomeExp;
        }

        // Return total liquidation payout
        return numeratorSum36.liquidatorTotalReward({
            currentExpSum: market.expSum, tokenDecimalScaler: marketProxy.TOKEN_DECIMAL_SCALER()
        });
    }
}
