// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {Invariants_Base} from "../InvariantBase.t.sol";
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Interfaces
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";

// Libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

abstract contract Lmsr_Invariants is Invariants_Base, DelphiTestUtils {
    // ========== LIBRARIES ==========
    using SafeCast for uint256;
    using Math for uint256;
    using LmsrMath for uint256;

    // ========== MODIFIERS ==========
    modifier ifSettled() {
        if (handler.marketProxy().marketStatus() == ILmsrMarketTypes.MarketStatus.SETTLED) {
            _;
        }
    }

    modifier ifNotSettled() {
        if (handler.marketProxy().marketStatus() != ILmsrMarketTypes.MarketStatus.SETTLED) {
            _;
        }
    }

    //  ========== OUTCOME SUPPLIES ==========

    function invariant_Supplies_AllZeroAtStart() external view ifDeployed ifNoTradesYet {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = market.config.outcomeCount;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Ensure outcome supply is zero
            assertEq(marketProxy.totalSupply(outcomeIdx), 0, "outcome supply not zero at start");
        }
    }

    function invariant_Supplies_NotBetweenZeroAndMinSharesDelta() external view ifDeployed {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = market.config.outcomeCount;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Check if 0 < outcome supply < min shares delta
            bool isBetweenZeroAndMinSharesDelta =
                (marketProxy.totalSupply(outcomeIdx) > 0
                    && marketProxy.totalSupply(outcomeIdx) < handler.minSharesDelta());

            // Ensure outcome supply is not between zero and min shares delta
            assertFalse(isBetweenZeroAndMinSharesDelta, "outcome supply is between zero and min shares delta");
        }
    }

    // ========== OUTCOME EXPs ==========

    function invariant_Exps_AllOneAtStart() external view ifDeployed ifNoTradesYet {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = market.config.outcomeCount;

        // Calculate expected initial exp
        uint256 expectedInitialExp = 1e18;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Ensure outcome supply is zero
            assertEq(
                market.config.b.outcomeExp(marketProxy.totalSupply(outcomeIdx)),
                expectedInitialExp,
                "outcome exp not equal at start"
            );
        }
    }

    function invariant_Exps_AtLeastOne() external view ifDeployed {
        // Get market
        ILmsrMarket market = handler.marketProxy();

        // Get market outcome count
        ILmsrMarket.Market memory marketInfo = market.getMarket();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketInfo.config.outcomeCount; outcomeIdx++) {
            // Get outcome exp
            uint256 outcomeExp = marketInfo.config.b.outcomeExp(market.totalSupply(outcomeIdx));

            // Ensure outcome exp is at least 1
            assertGe(outcomeExp, 1e18, "outcome exp not >= 1");
        }
    }

    function invariant_Exps_BelowExpSum() external view ifDeployed {
        // Get market
        ILmsrMarket market = handler.marketProxy();

        // Get market outcome count
        ILmsrMarket.Market memory marketInfo = market.getMarket();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketInfo.config.outcomeCount; outcomeIdx++) {
            // Get outcome exp
            uint256 outcomeExp = marketInfo.config.b.outcomeExp(market.totalSupply(outcomeIdx));

            // Ensure outcome exp is less than exp sum
            assertLt(outcomeExp, marketInfo.expSum, "outcome exp not < exp sum");
        }
    }

    function invariant_ExpsSum_EqualsExpSum() external view ifDeployed {
        // Get market
        ILmsrMarket market = handler.marketProxy();

        // Get market outcome count
        ILmsrMarket.Market memory marketInfo = market.getMarket();

        // Initialize exp sum
        uint256 expSum;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketInfo.config.outcomeCount; outcomeIdx++) {
            // Add to exp sum
            expSum += marketInfo.config.b.outcomeExp(market.totalSupply(outcomeIdx));
        }

        // Ensure exp sum equals market exp sum
        assertEq(expSum, marketInfo.expSum, "exp sum not = market exp sum");
    }

    // ========== OUTCOME PROBABILITIES ==========

    function invariant_Probabilities_EqualAtStart() external view ifDeployed ifNoTradesYet ifNotSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = market.config.outcomeCount;

        // Calculate expected initial probability
        uint256 expectedInitialProbability = 1e18 / marketOutcomeCount;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            assertEq(
                marketProxy.spotImpliedProbability(outcomeIdx),
                expectedInitialProbability,
                "outcome probabilities not equal at start"
            );
        }
    }

    function invariant_Unsettled_Outcome_Probabilities_AboveZero() external view ifDeployed ifNotSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = marketProxy.getMarket().config.outcomeCount;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Ensure outcome probability is greater than zero
            assertGt(marketProxy.spotImpliedProbability(outcomeIdx), 0, "outcome probability not > 0");
        }
    }

    function invariant_Unsettled_Outcome_Probabilities_BelowOne() external view ifDeployed ifNotSettled {
        // Get market
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = marketProxy.getMarket().config.outcomeCount;

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Validate
            assertLt(marketProxy.spotImpliedProbability(outcomeIdx), ONE, "outcome probability not < ONE");
        }
    }

    function invariant_Winning_Outcome_Probability_EqualsOne() external view ifDeployed ifSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get winning outcome
        uint256 winningOutcomeIdx = marketProxy.getMarket().winningOutcomeIdx;

        // Validate
        assertEq(marketProxy.spotImpliedProbability(winningOutcomeIdx), ONE, "outcome probability not = ONE");
    }

    function invariant_Losing_Outcome_Probability_EqualsZero() external view ifDeployed ifSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < market.config.outcomeCount; outcomeIdx++) {
            // Skip winning outcome
            if (outcomeIdx == market.winningOutcomeIdx) {
                continue;
            }

            // Validate
            assertEq(marketProxy.spotImpliedProbability(outcomeIdx), 0, "outcome probability not = 0");
        }
    }

    function invariant_ProbabilitiesSum_EqualsOne() external view ifDeployed {
        // Get market
        ILmsrMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // Initialize Probabilities Sum
        uint256 probabilitiesSum;

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            probabilitiesSum += market.spotImpliedProbability(outcomeIdx);
        }

        // Validate
        assertApproxEqAbs(probabilitiesSum, ONE, BASIS_POINT, "probabilities sum not approx = ONE");
    }

    // ========== OUTCOME PRICES ==========

    function invariant_Prices_EqualAtStart() external view ifDeployed ifNoTradesYet ifNotSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = market.config.outcomeCount;

        // Calculate expected initial price
        uint256 expectedInitialPrice = 1e18 / (marketOutcomeCount * handler.tokenDecimalScaler());

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            assertEq(marketProxy.spotPrice(outcomeIdx), expectedInitialPrice, "outcome prices not equal at start");
        }
    }

    // Note: No invariant_Unsettled_Outcome_Prices_AboveZero, as spotPrice always truncates to zero. But its not used internally, so not a problem.

    function invariant_Unsettled_Outcome_Prices_BelowOne() external view ifDeployed ifNotSettled {
        // Get market
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = marketProxy.getMarket().config.outcomeCount;

        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Ensure outcome price is less than 100%
            assertLt(marketProxy.spotPrice(outcomeIdx) * tokenDecimalScaler, ONE, "outcome price not < 100%");
        }
    }

    function invariant_Winning_Outcome_Price_EqualsOne() external view ifDeployed ifSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get winning outcome
        uint256 winningOutcomeIdx = marketProxy.getMarket().winningOutcomeIdx;

        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // Validate
        assertEq(marketProxy.spotPrice(winningOutcomeIdx) * tokenDecimalScaler, ONE, "outcome price not = ONE");
    }

    function invariant_Losing_Outcome_Price_EqualsZero() external view ifDeployed ifSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < market.config.outcomeCount; outcomeIdx++) {
            // Skip winning outcome
            if (outcomeIdx == market.winningOutcomeIdx) {
                continue;
            }

            // Validate
            assertEq(marketProxy.spotPrice(outcomeIdx) * tokenDecimalScaler, 0, "outcome price not = 0");
        }
    }

    function invariant_PricesSum_EqualsOne() external view ifDeployed {
        // Get market
        ILmsrMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // Initialize prices sum
        uint256 pricesSum;

        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Add to prices sum
            pricesSum += market.spotPrice(outcomeIdx) * tokenDecimalScaler;
        }

        // Ensure prices sum equals 100%
        assertApproxEqAbsDecimal(pricesSum, ONE, TOLERANCE, 18, "prices sum not == 100%");
    }

    // ========== PROBABILITY/PRICE RELATIONSHIPS ==========

    function invariant_PriceEqualsProbability() external view ifDeployed {
        // Get market
        ILmsrMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Get outcome price
            uint256 outcomePrice = market.spotPrice(outcomeIdx) * tokenDecimalScaler;

            // Get outcome probability
            uint256 outcomeProbability = market.spotImpliedProbability(outcomeIdx);

            // Ensure price equals probability
            assertApproxEqAbs(outcomePrice, outcomeProbability, BASIS_POINT, "price not = probability");
        }
    }

    // ========== MARKET BALANCE ==========

    function invariant_Balance_IsCorrect() external view ifDeployed {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get token
        IERC20Metadata token = handler.token();

        // Get market proxy balance
        uint256 marketBalance = token.balanceOf(address(marketProxy));

        // Get keeper reserve
        uint256 keeperReserve = marketProxy.keeperFeePaid() ? 0 : marketProxy.KEEPER_FEE();

        // Get oracle reserve
        uint256 oracleReserve = marketProxy.oracleFeePaid() ? 0 : marketProxy.ORACLE_FEE();

        // Get market creator claimable
        uint256 marketCreatorClaimable = marketProxy.marketCreatorClaimable();

        // Validate market balance
        assertEq(
            marketBalance,
            market.pool + market.tradingFees + keeperReserve + oracleReserve + marketCreatorClaimable,
            "unexpected market balance"
        );
    }

    // ========== MARKET POOL ==========

    function invariant_Pool_CoversMaxPayout() external view ifDeployed {
        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get market status
        ILmsrMarketTypes.MarketStatus marketStatus = marketProxy.marketStatus();

        // Initialize max payout
        uint256 maxPayout;

        // If market is OPEN or AWAITING_SETTLEMENT, maxPayout = Highest outcome supply
        if (
            marketStatus == ILmsrMarketTypes.MarketStatus.OPEN
                || marketStatus == ILmsrMarketTypes.MarketStatus.AWAITING_SETTLEMENT
        ) {
            // Max payout = Highest outcome supply
            // Note: total (not external) supply, because redemptions/liquidations haven't happened yet
            maxPayout = _highestOutcomeSupply(marketProxy) / tokenDecimalScaler;

            // If market is SETTLED, maxPayout = Winning outcome external supply
        } else if (marketProxy.marketStatus() == ILmsrMarketTypes.MarketStatus.SETTLED) {
            // Max payout = Winning outcome external supply
            // Note: external (not total) supply, because redemptions might have already happened
            maxPayout = handler.externalSupply(market.winningOutcomeIdx) / tokenDecimalScaler;

            // If market is EXPIRED or FAILED
        } else {
            // Skip
            // Note: invariant_UnsettledPool_CoversSumOfExternalOutcomeValues already covers this (and also asserts it for the OPEN and AWAITING_SETTLEMENT states)
            return;
        }

        // Ensure pool covers max payout
        assertGe(market.pool, maxPayout, "pool does not cover the max payout");
    }

    function invariant_UnsettledPool_CoversSumOfExternalOutcomeValues() external view ifDeployed ifNotSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Initialize numerator sum
        uint256 numeratorSum36;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < market.config.outcomeCount; outcomeIdx++) {
            // Get outcome total supply
            uint256 outcomeTotalSupply = marketProxy.totalSupply(outcomeIdx);

            // Calculate outcome exp
            // Note: Use total (not external) supply here (to not change the prices)
            uint256 outcomeExp = market.config.b.outcomeExp(outcomeTotalSupply);

            // Add to numerator sum
            // Note: Use external (not total) supply here (as some liquidations might have already happened)
            numeratorSum36 += handler.externalSupply(outcomeIdx) * outcomeExp;
        }

        // Calculate sum of outcome values
        uint256 sumOfExternalOutcomeValues = numeratorSum36 / (market.expSum * handler.tokenDecimalScaler());

        // Ensure pool covers sum of external outcome values
        assertGe(
            market.pool, sumOfExternalOutcomeValues, "unsettled pool does not cover the sum of external outcome values"
        );
    }

    // ========== SELL ==========

    function invariant_CanAlwaysSellEverything() external ifDeployed {
        // Get vars
        uint256 minSharesDelta = handler.minSharesDelta();
        bytes4[] memory allowedSellErrors = _quoteSellExactInAllowedErrors();

        // Get market id
        ILmsrMarket market = handler.marketProxy();

        // Get market status
        ILmsrMarketTypes.MarketStatus marketStatus = market.marketStatus();

        // If market is not open, skip
        if (marketStatus != ILmsrMarketTypes.MarketStatus.OPEN) {
            return;
        }

        // Get users with shares
        address[] memory usersWithShares = handler.usersWithShares();

        // For each user with shares
        for (uint256 i = 0; i < usersWithShares.length; i++) {
            // Get user
            address user = usersWithShares[i];

            // Get user outcomes with shares
            uint256[] memory outcomesWithShares = handler.outcomesWithUserShares(user);

            // For each outcome where the user has shares
            for (uint256 j = 0; j < outcomesWithShares.length; j++) {
                // Get outcome idx
                uint256 outcomeIdx = outcomesWithShares[j];

                // Get user shares for outcome
                uint256 userShares = market.balanceOf(user, outcomeIdx);

                // If user shares are too low, continue
                if (userShares < minSharesDelta) {
                    continue;
                }

                // Switch to user
                _useNewSender(user);

                // Try to sell all shares
                try handler.gateway()
                    .sellExactIn({marketProxy: market, outcomeIdx: outcomeIdx, sharesIn: userShares, minTokensOut: 0}) {

                // If there is an error, ensure it's an allowed error
                }
                catch (bytes memory err) {
                    _handleCatch(err, allowedSellErrors);
                }
            }
        }
    }

    // ========== REDEEM ==========

    function invariant_CanAlwaysRedeemEverything() external ifDeployed ifSettled {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get gateway
        ILmsrGateway gateway = handler.gateway();

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Get token decimal scaler
        uint256 tokenDecimalScaler = handler.tokenDecimalScaler();

        // Get winning outcome idx
        uint256 winningOutcomeIdx = market.winningOutcomeIdx;

        // Get users with winning outcome shares
        address[] memory usersWithWinningOutcomeShares = handler.usersWithOutcomeShares(winningOutcomeIdx);

        // Initialize unredeemed shares
        uint256 unredeemedShares;

        // For each user with winning outcome shares
        for (uint256 i = 0; i < usersWithWinningOutcomeShares.length; i++) {
            // Get user
            address user = usersWithWinningOutcomeShares[i];

            // Get user winning outcome shares
            uint256 userWinningOutcomeShares = marketProxy.balanceOf(user, winningOutcomeIdx);

            // If user doesn't have enough winning outcome shares to redeem
            if (userWinningOutcomeShares < tokenDecimalScaler) {
                // Add to unredeemed shares
                unredeemedShares += userWinningOutcomeShares;
            } else {
                // Switch to user
                _useNewSender(user);

                // Redeem
                gateway.redeem({marketProxy: marketProxy});
            }
        }

        // Get token decimals
        uint256 tokenDecimals = handler.tokenDecimals();

        // Ensure all shares are accounted for
        assertEqDecimal(
            marketProxy.balanceOf(address(marketProxy), winningOutcomeIdx) + unredeemedShares,
            marketProxy.totalSupply(winningOutcomeIdx),
            tokenDecimals,
            "_redeem: not all shares accounted for"
        );

        // Ensure market pool is empty
        assertApproxEqAbsDecimal(
            marketProxy.getMarket().pool,
            0,
            TOLERANCE / marketProxy.TOKEN_DECIMAL_SCALER(),
            tokenDecimals,
            "_redeem: market pool not empty after all redemptions"
        );

        // Ensure trading fees are empty
        assertEqDecimal(
            marketProxy.getMarket().tradingFees,
            0,
            tokenDecimals,
            "_redeem: market trading fees not empty after all redemptions"
        );

        // Ensure market has no tokens
        assertApproxEqAbsDecimal(
            handler.token().balanceOf(address(marketProxy)),
            0,
            TOLERANCE / marketProxy.TOKEN_DECIMAL_SCALER(),
            tokenDecimals,
            "_redeem: market token balance not zero after all redemptions"
        );
    }

    // ========== LIQUIDATE ==========

    function invariant_CanAlwaysLiquidateEverything_AndLiquidationsAreOrderIndependent() external ifDeployed {
        // Get market proxy
        ILmsrMarket marketProxy = handler.marketProxy();

        // Get market status
        ILmsrMarketTypes.MarketStatus marketStatus = marketProxy.marketStatus();

        // If market is not EXPIRED or FAILED, skip
        if (
            marketStatus != ILmsrMarketTypes.MarketStatus.EXPIRED
                && marketStatus != ILmsrMarketTypes.MarketStatus.FAILED
        ) {
            return;
        }

        // Initialize arrays
        uint256[] memory sharesInPerOutcome = new uint256[](marketProxy.getMarket().config.outcomeCount);
        uint256[] memory tokensOutPerOutcome = new uint256[](marketProxy.getMarket().config.outcomeCount);

        // Get gateway
        ILmsrGateway gateway = handler.gateway();

        // Get users with shares
        address[] memory usersWithShares = handler.usersWithShares();

        // Initialize unliquidated shares array
        uint256[] memory unliquidatedShares = new uint256[](marketProxy.getMarket().config.outcomeCount);

        // For each user with shares
        for (uint256 i = 0; i < usersWithShares.length; i++) {
            // Get liquidator
            address liquidator = usersWithShares[i];

            // Get outcomes with liquidator shares
            uint256[] memory outcomesWithLiquidatorShares = handler.outcomesWithUserShares(liquidator);

            // For each outcome with liquidator shares
            for (uint256 j = 0; j < outcomesWithLiquidatorShares.length; j++) {
                // Get outcome idx
                uint256 outcomeIdx = outcomesWithLiquidatorShares[j];

                // Build outcome indices array
                uint256[] memory outcomeIndices = new uint256[](1);
                outcomeIndices[0] = outcomeIdx;

                // Switch to liquidator
                _useNewSender(liquidator);

                // Liquidate
                try gateway.liquidate({marketProxy: marketProxy, outcomeIndices: outcomeIndices}) returns (
                    uint256[] memory sharesIn, uint256 totalTokensOut
                ) {
                    // If sharesIn is not set
                    if (sharesInPerOutcome[outcomeIdx] == 0) {
                        // Ensure sharesIn is 0 too
                        assertEq(tokensOutPerOutcome[outcomeIdx], 0, "tokensOut is not 0");

                        // Set them
                        sharesInPerOutcome[outcomeIdx] = sharesIn[0];
                        tokensOutPerOutcome[outcomeIdx] = totalTokensOut;

                        // If sharesIn and tokensOut are already set
                    } else {
                        /* Calculate max delta
                        *
                        * 1. First, how to ensure liquidations are order independent?
                        * Instead of dividing and comparing ratios (tokens per share), use cross-multiplication (more precision)
                        * liquidator1TokensPerShare = liquidatorNTokensPerShare
                        * liquidator1TokensPerShare = liquidator1TokensOut / liquidator1SharesIn
                        * liquidatorNTokensPerShare = liquidatorNTokensOut / liquidatorNSharesIn
                        * liquidator1TokensOut / liquidator1SharesIn = liquidatorNTokensOut / liquidatorNSharesIn
                        * liquidator1TokensOut * liquidatorNSharesIn = liquidatorNTokensOut * liquidator1SharesIn (the equality that must hold)
                        *
                        * 2. Therefore:
                        * delta = (liquidator1TokensOut * liquidatorNSharesIn) - (liquidatorNTokensOut * liquidator1SharesIn)
                        *
                        * 3. Now, where could this delta come from?
                        * Every liquidation performs a division (which truncates), losing a uint strictly below 1 (let's call it liquidatorRemainder)
                        * Therefore:
                        * liquidator1TokensOut = outcomePrice * liquidator1SharesIn − liquidator1Remainder
                        * liquidatorNTokensOut = outcomePrice * liquidatorNSharesIn − liquidatorNRemainder
                        *
                        * 4. Now, let's substitute, and calculate the delta:
                        *
                        * Left side:
                        * liquidator1TokensOut * liquidatorNSharesIn
                        * (outcomePrice * liquidator1SharesIn − liquidator1Remainder) * liquidatorNSharesIn
                        * (outcomePrice * liquidator1SharesIn * liquidatorNSharesIn)  −  (liquidator1Remainder * liquidatorNSharesIn)
                        *
                        * Right side:
                        * liquidatorNTokensOut * liquidator1SharesIn
                        * (outcomePrice * liquidatorNSharesIn − liquidatorNRemainder) * liquidator1SharesIn
                        * (outcomePrice * liquidatorNSharesIn * liquidator1SharesIn)  −  (liquidatorNRemainder * liquidator1SharesIn)
                        *
                        * delta = (
                            (outcomePrice * liquidator1SharesIn * liquidatorNSharesIn)  −  (liquidator1Remainder * liquidatorNSharesIn) -
                            ((outcomePrice * liquidatorNSharesIn * liquidator1SharesIn)  −  (liquidatorNRemainder * liquidator1SharesIn))
                        )
                        * delta = (
                            (outcomePrice * liquidator1SharesIn * liquidatorNSharesIn)  −  (liquidator1Remainder * liquidatorNSharesIn) -
                            (outcomePrice * liquidatorNSharesIn * liquidator1SharesIn)  +  (liquidatorNRemainder * liquidator1SharesIn)
                        )
                        * delta = (
                            − (liquidator1Remainder * liquidatorNSharesIn) + (liquidatorNRemainder * liquidator1SharesIn)
                        )
                        * delta = (liquidatorNRemainder * liquidator1SharesIn) - (liquidator1Remainder * liquidatorNSharesIn)
                        *
                        * 5. Now, let's calculate the max delta (the worst-case scenario delta):
                        * 0 ≤ liquidatorNRemainder < 1, so: liquidatorNRemainder * liquidator1SharesIn < liquidator1SharesIn
                        * 0 ≤ liquidator1Remainder < 1, so: liquidator1Remainder * liquidatorNSharesIn < liquidatorNSharesIn
                        *
                        * Therefore, the max delta is the max of the two amounts lost due to truncation:
                        * maxDelta = someAmountBelowLiquidator1SharesIn - someAmountBelowLiquidatorNSharesIn
                        * maxDelta = max(liquidator1SharesIn, liquidatorNSharesIn)
                        */
                        uint256 maxDelta = Math.max(sharesInPerOutcome[outcomeIdx], sharesIn[0]);

                        // Assert
                        assertApproxEqAbs(
                            tokensOutPerOutcome[outcomeIdx] * sharesIn[0],
                            totalTokensOut * sharesInPerOutcome[outcomeIdx],
                            maxDelta,
                            "liquidations are not order independent"
                        );
                    }

                    // If liquidation fails
                } catch (bytes memory err) {
                    // Handle error
                    _handleCatch(err, _liquidateAllowedErrors());

                    // Add to unliquidated shares
                    unliquidatedShares[outcomeIdx] += marketProxy.balanceOf(liquidator, outcomeIdx);
                }
            }
        }

        // Get token decimals
        uint256 tokenDecimals = handler.tokenDecimals();

        // Get outcome count
        uint256 outcomeCount = marketProxy.getMarket().config.outcomeCount;

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < outcomeCount; outcomeIdx++) {
            // Ensure market has all liquidated shares
            assertEqDecimal(
                marketProxy.balanceOf(address(marketProxy), outcomeIdx),
                marketProxy.totalSupply(outcomeIdx) - unliquidatedShares[outcomeIdx],
                tokenDecimals,
                "_liquidate: not all shares liquidated for outcome index"
            );
        }
    }

    // ========== OTHER ==========

    function invariant_RoundTrip() external ifDeployed {
        // If market not open, skip
        if (handler.marketProxy().marketStatus() != ILmsrMarketTypes.MarketStatus.OPEN) {
            return;
        }

        // Get market config
        ILmsrMarket.MarketConfig memory marketConfig = handler.marketProxyConfig();

        // Pick trader
        address trader = makeAddr("trader");

        // Get min shares delta
        uint256 minSharesDelta = handler.minSharesDelta();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < marketConfig.outcomeCount; outcomeIdx++) {
            // Get max shares out
            uint256 maxSharesOut = _maxSharesOut(handler.marketProxy(), outcomeIdx);

            // Ensure min shares delta is less than max shares out
            if (minSharesDelta > maxSharesOut) {
                continue;
            }

            // Pick shares delta
            uint256 seed = handler.consumeInvariantSeed();
            uint256 sharesDelta = bound(seed, minSharesDelta, maxSharesOut);

            (bool success,, uint256 tokensIn) = _tryQuoteBuyExactOut({
                marketGateway: handler.gateway(),
                marketProxy: handler.marketProxy(),
                outcomeIdx: outcomeIdx,
                sharesOut: sharesDelta
            });

            if (!success) {
                continue;
            }

            (uint256 valueAfterBuy,) = tokensIn.deductFee(marketConfig.tradingFee);
            (uint256 valueAfterSell,) = valueAfterBuy.deductFee(marketConfig.tradingFee);

            /* `valueAfterSell` models fees only, so it overstates what the round trip actually returns.
             * The gateway rounds against the trader on both legs: `quoteBuyExactOut` ceils `netTokensIn`
             * and widens the exp/ln bounds, while `quoteSellExactIn` floors `grossTokensOut` and narrows
             * them. Those roundings cost a few raw token units, which has two consequences here:
             * the sell returns slightly less than `valueAfterSell`, and — once the units push the proceeds
             * under MIN_TOKENS_DELTA — `quoteSellExactIn` rejects the sell outright, which is correct
             * dust protection rather than a broken round trip.
             *
             * The whole rounding budget stays below MIN_TOKENS_DELTA for every valid `b`: the truncations
             * cost 3 raw units and the exp/ln margins cost b * ~4200 / (1e18 * TOKEN_DECIMAL_SCALER),
             * which is under one MIN_TOKENS_DELTA as long as 4200 * b < 1e34 — true even at MAX_B (5e24).
             * So requiring one extra MIN_TOKENS_DELTA of headroom both keeps the sell reachable and keeps
             * the rounding loss well inside the tolerance asserted below.
             */
            uint256 minTokensDelta = handler.gateway().MIN_TOKENS_DELTA();
            if (valueAfterSell < minTokensDelta + minTokensDelta) {
                continue;
            }

            // Buy
            (bool successBuy,,) = _buy({
                buyer: trader,
                marketGateway: handler.gateway(),
                marketProxy: handler.marketProxy(),
                outcomeIdx: outcomeIdx,
                sharesOut: sharesDelta,
                maxTokensIn: type(uint256).max
            });

            require(successBuy, "Buy should be successfull after quote");

            // Sell
            (bool successSell,, uint256 tokensOut) = _sell({
                seller: trader,
                marketGateway: handler.gateway(),
                marketProxy: handler.marketProxy(),
                outcomeIdx: outcomeIdx,
                sharesIn: sharesDelta,
                minTokensOut: 0
            });

            // Ensure sell is successful
            assertTrue(successSell, "should always be able to sell after buy");

            // Ensure tokens out is less than tokens in
            assertLtDecimal(
                tokensOut, tokensIn, handler.tokenDecimals(), "tokensOut not < tokensIn (arbitrage is possible)"
            );

            // Validate rounding errors
            assertApproxEqRelDecimal(
                tokensOut, valueAfterSell, 2 * BASIS_POINT, handler.tokenDecimals(), "rounding errors too big"
            );
        }
    }

    // ========== HELPERS ==========

    function _highestOutcomeSupply(ILmsrMarket marketProxy) internal view returns (uint256 highestOutcomeSupply) {
        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < market.config.outcomeCount; outcomeIdx++) {
            // Get outcome supply
            uint256 outcomeSupply = marketProxy.totalSupply(outcomeIdx);

            // If outcome supply is higher than highest outcome supply
            if (outcomeSupply > highestOutcomeSupply) {
                // Update highest outcome supply
                highestOutcomeSupply = outcomeSupply;
            }
        }
    }
}
