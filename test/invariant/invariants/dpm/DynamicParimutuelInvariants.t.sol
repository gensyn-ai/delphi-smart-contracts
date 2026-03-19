// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {Invariants_Base} from "../InvariantBase.t.sol";
import {DelphiTestUtils} from "test/utils/DelphiTestUtils.t.sol";

// Libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Interface
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DynamicParimutuelMath} from "src/delphi/dynamicParimutuel/math/DynamicParimutuelMath.sol";

abstract contract DynamicParimutuel_Invariants is Invariants_Base, DelphiTestUtils {
    // ========== LIBRARIES ==========
    using SafeCast for uint256;
    using Math for uint256;
    using DynamicParimutuelMath for uint256;

    // ========== OUTCOME PRICES ==========

    function invariant_Prices_BelowK() external view ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // Get market k
        uint256 k = market.getMarket().config.k;

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Get outcome price
            uint256 outcomePrice = market.spotPrice(outcomeIdx);

            // Ensure price doesn't exceed k
            assertLe(outcomePrice, k, "outcome price is not <= k");
        }
    }

    function invariant_Prices_Sum() external view ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market config
        IDynamicParimutuelMarket.MarketConfig memory marketConfig = market.getMarket().config;

        // Get token decimals
        uint256 tokenDecimals = market.TOKEN().decimals();

        // Calculate target prices sum
        uint256 k = marketConfig.k / market.TOKEN_DECIMAL_SCALER();
        uint256 maxPricesSum = k.mulDiv((marketConfig.outcomeCount * 1e36).sqrt(), ONE); // k * sqrt(outcomeCount)

        // Initialize prices sum
        uint256 pricesSum;

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketConfig.outcomeCount; outcomeIdx++) {
            pricesSum += market.spotPrice(outcomeIdx);
        }

        assertGeDecimal(pricesSum, _adjustDown(k, BASIS_POINT), tokenDecimals, "prices sum not >= k");
        assertLeDecimal(pricesSum, _adjustUp(maxPricesSum, BASIS_POINT), tokenDecimals, "prices sum not <= kSqrt");
    }

    function invariant_PricesSquare_Sum() external view ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        IDynamicParimutuelMarket.MarketConfig memory marketConfig = market.getMarket().config;
        uint256 marketOutcomeCount = marketConfig.outcomeCount;
        uint256 k = marketConfig.k;

        uint256 priceSquareSum = 0;
        for (uint256 i = 0; i < marketOutcomeCount; i++) {
            uint256 price = market.spotPrice(i);
            priceSquareSum += price * price;
        }
        uint256 tokenDecimalScalar = market.TOKEN_DECIMAL_SCALER();
        uint256 kSquared = k * k / (tokenDecimalScalar * tokenDecimalScalar);
        assertApproxEqRelDecimal(
            priceSquareSum, // left
            kSquared, // right
            BASIS_POINT, // tolerance
            handler.tokenDecimals(), // decimals
            "Sum of prices squares should be k squared"
        );
    }

    function invariant_PoolValueMatchesSumOfOutcomeValues() external view ifDeployed {
        IDynamicParimutuelMarket market = handler.marketProxy();

        IDynamicParimutuelMarketTypes.MarketStatus marketStatus = market.marketStatus();
        if (
            marketStatus == IDynamicParimutuelMarketTypes.MarketStatus.SETTLED
                || marketStatus == IDynamicParimutuelMarketTypes.MarketStatus.EXPIRED
        ) {
            return;
        }

        uint256 calculatedPool = 0;
        IDynamicParimutuelMarket.Market memory marketInfo = market.getMarket();
        uint256 marketOutcomeCount = marketInfo.config.outcomeCount;
        for (uint256 i = 0; i < marketOutcomeCount; i++) {
            uint256 totalSupply = market.totalSupply(i);
            uint256 spotPrice = market.spotPrice(i);

            calculatedPool += totalSupply.mulDiv(spotPrice, ONE);
        }

        assertApproxEqRelDecimal(
            calculatedPool, // left
            marketInfo.pool, // right
            2 * BASIS_POINT, // tolerance: 0.02%
            handler.tokenDecimals(), // decimals
            "Pool value should equal the sum of outcome values"
        );
    }

    // ========== OUTCOME PROBABILITIES ==========

    function invariant_Probabilities_BelowOne() external view ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Validate
            assertLt(market.spotImpliedProbability(outcomeIdx), ONE, "outcome probability not < ONE");
        }
    }

    function invariant_Probabilities_SumEqualsOne() external view ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // Initialize Probabilities Sum
        uint256 probabilitiesSum;

        // For each model in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            probabilitiesSum += market.spotImpliedProbability(outcomeIdx);
        }

        // Validate
        assertApproxEqRel(probabilitiesSum, ONE, BASIS_POINT, "probabilities sum not approx = ONE");
    }

    // ========== OUTCOME SUPPLIES ==========

    function invariant_Supplies_AboveZero() external view ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market outcome count
        uint256 marketOutcomeCount = market.getMarket().config.outcomeCount;

        // For each outcome in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Get outcome supply
            uint256 outcomeSupply = market.totalSupply(outcomeIdx);

            // Ensure outcome supply is > 0
            assertGt(outcomeSupply, 0, "outcome supply is not > 0");
        }
    }

    // ========== OUTCOME TERMS (supply^2) ==========

    function invariant_Terms_BelowSumTerm() external view ifDeployed {
        // Get market id
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market info
        IDynamicParimutuelMarket.Market memory marketInfo = market.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = marketInfo.config.outcomeCount;

        // Get current sum term
        uint256 currentSumTerm36 = marketInfo.sumTerm36;

        // For each outcome in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Get outcome term
            uint256 outcomeTerm36 = market.totalSupply(outcomeIdx) ** 2;

            // Ensure that the outcome term is always < sum term
            assertLt(outcomeTerm36, currentSumTerm36, "outcome term is not < sum term");
        }
    }

    function invariant_Terms_SumEqualsSumTerm() external view ifDeployed {
        // Get market id
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market info
        IDynamicParimutuelMarket.Market memory marketInfo = market.getMarket();

        // Get market outcome count
        uint256 marketOutcomeCount = marketInfo.config.outcomeCount;

        // Initialize vars
        uint256 termSum36;

        // For each outcome in the market
        for (uint256 outcomeIdx = 0; outcomeIdx < marketOutcomeCount; outcomeIdx++) {
            // Add to term sum
            termSum36 += market.totalSupply(outcomeIdx) ** 2;
        }

        // Ensure sum(outcome) = market.currentSumTerm
        assertEq(termSum36, marketInfo.sumTerm36, "sum of outcome exps not = currentSumTerm");
    }

    // ========== PAYOUT TERMS ==========

    function invariant_PayoutTerms_AboveK() external view ifDeployed {}

    // ========== OTHER ==========

    function invariant_AssetsAreCorrect() external view ifDeployed {
        // Get prediction market token balance
        IERC20Metadata token = handler.token();

        // For each market
        IDynamicParimutuelMarket market = handler.marketProxy();
        IDynamicParimutuelMarket.Market memory marketInfo = market.getMarket();

        uint256 balance = token.balanceOf(address(market));
        assertEq(balance, marketInfo.pool + marketInfo.tradingFees, "token balance not correct");
    }

    function invariant_CanAlwaysSellEverything() external ifDeployed {
        // Get vars
        uint256 minSharesDelta = handler.minSharesDelta();
        bytes4[] memory allowedSellErrors = _quoteSellExactInAllowedErrors();

        // Get market id
        IDynamicParimutuelMarket market = handler.marketProxy();

        // Get market status
        IDynamicParimutuelMarketTypes.MarketStatus marketStatus = market.marketStatus();

        // If market is not open, skip
        if (marketStatus != IDynamicParimutuelMarketTypes.MarketStatus.OPEN) {
            return;
        }

        // Get users with shares
        address[] memory usersWithShares = handler.usersWithShares();

        // For each user with shares
        for (uint256 i = 0; i < usersWithShares.length; i++) {
            // Get user
            address user = usersWithShares[i];

            // Get user outcomes with shares
            uint256[] memory outcomesWithShares = handler.userOutcomesWithShares(user);

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
                try handler.dynamicParimutuelGateway()
                    .sellExactIn({marketProxy: market, outcomeIdx: outcomeIdx, sharesIn: userShares, minTokensOut: 0}) {

                // If there is an error, ensure it's an allowed error
                }
                catch (bytes memory err) {
                    _handleCatch(err, allowedSellErrors);
                }
            }
        }
    }

    function invariant_RoundTrip() external ifDeployed {
        // Get market
        IDynamicParimutuelMarket market = handler.marketProxy();

        // If market is not open, skip
        IDynamicParimutuelMarketTypes.MarketStatus marketStatus = market.marketStatus();

        // If market not open, exit
        if (marketStatus != IDynamicParimutuelMarketTypes.MarketStatus.OPEN) {
            return;
        }

        // Get market config
        IDynamicParimutuelMarket.MarketConfig memory marketConfig = handler.marketProxyConfig();
        uint256 tradingFee = marketConfig.tradingFee;
        uint256 decimals = handler.tokenDecimals();
        address trader = makeAddr("trader");
        uint256 marketOutcomeCount = marketConfig.outcomeCount;

        // For each outcome
        for (uint256 i = 0; i < marketOutcomeCount; i++) {
            // Pick shares delta
            uint256 sharesDelta = 1_000_000e18;

            // Buy
            (bool successBuy,, uint256 tokensIn) = _buy({
                buyer: trader,
                marketGateway: handler.dynamicParimutuelGateway(),
                marketProxy: market,
                outcomeIdx: i,
                sharesOut: sharesDelta,
                maxTokensIn: type(uint256).max
            });

            // If buy failed, continue
            if (!successBuy) {
                continue;
            }

            // Sell
            (bool successSell,, uint256 tokensOut) = _sell({
                seller: trader,
                marketGateway: handler.dynamicParimutuelGateway(),
                marketProxy: market,
                outcomeIdx: i,
                sharesIn: sharesDelta,
                minTokensOut: 0
            });

            // Ensure sell is successful
            assertTrue(successSell, "Should be able to sell after buy");

            // Ensure tokens out is less than tokens in
            assertLtDecimal(tokensOut, tokensIn, decimals, "arbitrage");

            // Validate rounding errors
            (uint256 valueAfterBuy,) = tokensIn.deductFee(tradingFee);
            (uint256 valueAfterSell,) = valueAfterBuy.deductFee(tradingFee);
            assertApproxEqRelDecimal(tokensOut, valueAfterSell, BASIS_POINT, decimals, "rounding errors too big");
        }
    }
}
