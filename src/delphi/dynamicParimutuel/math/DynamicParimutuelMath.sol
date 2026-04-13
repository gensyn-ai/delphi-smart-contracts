// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IDynamicParimutuelMathErrors} from "./IDynamicParimutuelMathErrors.sol";

/// @title DynamicParimutuelMath
/// @notice Library implementing the mathematical operations for Dynamic-Parimutuel Prediction Markets.
/// @dev All rounding is performed against the user (tokensIn rounded up, tokensOut rounded down) to prevent value extraction.
library DynamicParimutuelMath {
    // ===== LIBRARIES =====
    using Math for uint256;

    /// @notice Given a gross amount (inclusive of fees), splits it into the net amount and the fee amount.
    /// @param grossAmount The total amount, including the fee.
    /// @param tradingFee The fee percentage (e.g., 1e16 for 1%).
    /// @return netAmount The amount after deducting the fee.
    /// @return feeAmount The calculated fee amount.
    function deductFee(uint256 grossAmount, uint256 tradingFee)
        internal
        pure
        returns (uint256 netAmount, uint256 feeAmount)
    {
        netAmount = mulDivDown(grossAmount, 1e18 - tradingFee, 1e18); // Note: Down (against user)
        feeAmount = grossAmount - netAmount;
    }

    /// @notice Given a net amount (exclusive of fees), calculates the gross amount required to cover
    ///         the net amount plus its associated fee.
    /// @param netAmount The base amount, before adding the fee.
    /// @param tradingFee The fee percentage (e.g., 1e16 for 1%).
    /// @return grossAmount The total amount required to cover the net amount and the fee.
    /// @return feeAmount The calculated fee amount.
    function addFee(uint256 netAmount, uint256 tradingFee)
        internal
        pure
        returns (uint256 grossAmount, uint256 feeAmount)
    {
        grossAmount = mulDivUp(netAmount, 1e18, 1e18 - tradingFee); // Note: Up (against user)
        feeAmount = grossAmount - netAmount;
    }

    /// @notice Validates that a buy is economically sound: the tokens paid cover the cost of the shares minted.
    /// @dev Derivation:
    /* tokensIn >= c1 - c0
     * tokensIn >= k * sqrt(newSumTerm) - k * sqrt(currentSumTerm)
     * tokensIn >= k * ( sqrt(newSumTerm) - sqrt(currentSumTerm) )
     * tokensIn >= k * ( sqrt( currentSumTerm - modelSupply^2 + (modelSupply + sharesOut)^2 ) - sqrt(currentSumTerm) )
     * tokensIn >= k * ( sqrt( currentSumTerm - modelSupply^2 + modelSupply^2 + 2*modelSupply*sharesOut + sharesOut^2) - sqrt(currentSumTerm) )
     * tokensIn >= k * ( sqrt( currentSumTerm + 2*modelSupply*sharesOut + sharesOut^2) - sqrt(currentSumTerm) )
     * tokensIn >= k * ( sqrt( currentSumTerm + sharesOut * (2*modelSupply + sharesOut) - sqrt(currentSumTerm) )
     */
    /// @param k The liquidity depth parameter.
    /// @param currentSumTerm36 The current sum of squared supplies (36 decimal precision).
    /// @param modelCurrentSupply The current supply of the outcome being bought.
    /// @param tokensIn The net tokens in (after fees).
    /// @param sharesOut The number of shares to receive.
    /// @param tokenDecimalScalar The token decimal scaler (10^(18-decimals)).
    /// @return newSumTerm36 The updated sum term after the buy.
    /// @return valid True if the buy is economically valid.
    function buyIsValid(
        uint256 k,
        uint256 currentSumTerm36,
        uint256 modelCurrentSupply,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 tokenDecimalScalar
    ) internal pure returns (uint256 newSumTerm36, bool valid) {
        // Checks: Validate tokens in
        if (tokensIn == 0) {
            revert IDynamicParimutuelMathErrors.ZeroTokensIn();
        }

        // Checks: Validate shares out
        if (sharesOut == 0) {
            revert IDynamicParimutuelMathErrors.ZeroSharesOut();
        }

        // Calculate new sum term
        // Note: No rounding, to not propagate error to future trades
        newSumTerm36 = currentSumTerm36 + sharesOut * ((2 * modelCurrentSupply) + sharesOut); // Note: No rounding, to not propagate error to future trades

        // Checks: Validate new sum term
        assert(newSumTerm36 > currentSumTerm36);

        // Calculate sum term square roots
        uint256 c1Sqrt = sqrtUp(newSumTerm36); // Note: Up (against user)
        uint256 c0Sqrt = sqrtDown(currentSumTerm36); // Note: Down (against user)

        // Checks: Validate sum term square roots
        if (c1Sqrt == c0Sqrt) {
            revert IDynamicParimutuelMathErrors.BuyTooSmall();
        }

        // Check if buy is valid
        valid = tokensIn * tokenDecimalScalar * 1e18 >= k * (c1Sqrt - c0Sqrt);
    }

    /// @notice Validates that a sell is economically sound: the tokens received do not exceed the cost reduction.
    /// @dev Derivation:
    /* tokensOut <= c0 - c1
     * tokensOut <= k * sqrt(currentSumTerm) - k * sqrt(newSumTerm)
     * tokensOut <= k * (sqrt(currentSumTerm) - sqrt(newSumTerm))
     * tokensOut <= k * (sqrt(currentSumTerm) - sqrt(currentSumTerm - modelSupply^2 + (modelSupply - sharesIn)^2))
     * tokensOut <= k * (sqrt(currentSumTerm) - sqrt(currentSumTerm - modelSupply^2 + modelSupply^2 -2*modelSupply*sharesIn + sharesIn^2)
     * tokensOut <= k * (sqrt(currentSumTerm) - sqrt(currentSumTerm - 2*modelSupply*sharesIn + sharesIn^2)
     * tokensOut <= k * (sqrt(currentSumTerm) - sqrt(currentSumTerm - sharesIn * (2*modelSupply - sharesIn)
     */
    /// @param k The liquidity depth parameter.
    /// @param currentSumTerm36 The current sum of squared supplies (36 decimal precision).
    /// @param modelCurrentSupply The current supply of the outcome being sold.
    /// @param sharesIn The number of shares to sell.
    /// @param tokensOut The gross tokens out.
    /// @param tokenDecimalScalar The token decimal scaler (10^(18-decimals)).
    /// @return newSumTerm36 The updated sum term after the sell.
    /// @return valid True if the sell is economically valid.
    function sellIsValid(
        uint256 k,
        uint256 currentSumTerm36,
        uint256 modelCurrentSupply,
        uint256 sharesIn,
        uint256 tokensOut,
        uint256 tokenDecimalScalar
    ) internal pure returns (uint256 newSumTerm36, bool valid) {
        // Checks: Validate shares in
        if (sharesIn == 0) {
            revert IDynamicParimutuelMathErrors.ZeroSharesIn();
        }
        if (sharesIn > modelCurrentSupply) {
            revert IDynamicParimutuelMathErrors.SharesInExceedSupply(sharesIn, modelCurrentSupply);
        }

        // Checks: Validate tokens out
        if (tokensOut == 0) {
            revert IDynamicParimutuelMathErrors.ZeroTokensOut();
        }

        // Calculate new sum term
        // Note: No rounding, to not propagate error to future trades
        newSumTerm36 = currentSumTerm36 - sharesIn * ((2 * modelCurrentSupply) - sharesIn);

        // Checks: Validate new sum term
        assert(newSumTerm36 < currentSumTerm36);

        // Calculate sum term square roots
        uint256 c0Sqrt = sqrtDown(currentSumTerm36); // Note: Down (against user)
        uint256 c1Sqrt = sqrtUp(newSumTerm36); // Note: Up (against user)

        // Checks: Validate sum term square roots
        if (c1Sqrt > c0Sqrt) {
            revert IDynamicParimutuelMathErrors.SqrtOverlap();
        }
        if (c1Sqrt == c0Sqrt) {
            revert IDynamicParimutuelMathErrors.SellTooSmall();
        }

        // Check if sell is valid
        valid = tokensOut * tokenDecimalScalar * 1e18 <= k * (c0Sqrt - c1Sqrt);
    }

    /// @notice Calculates the spot price of a specific outcome.
    /// @dev Only used in external views, so no rounding direction is enforced.
    /// @param k The liquidity depth parameter.
    /// @param outcomeSupply The current supply of the outcome.
    /// @param currentSumTerm36 The current sum of squared supplies (36 decimal precision).
    /// @param tokenDecimalScalar The token decimal scaler (10^(18-decimals)).
    /// @return The spot price of the outcome.
    function spotPrice(uint256 k, uint256 outcomeSupply, uint256 currentSumTerm36, uint256 tokenDecimalScalar)
        internal
        pure
        returns (uint256)
    {
        // Note: This is only used in external views, so no need to round against the user
        return k.mulDiv(outcomeSupply, currentSumTerm36.sqrt() * tokenDecimalScalar);
    }

    /// @notice Calculates the spot implied probability of a specific outcome.
    /// @dev Only used in external views, so no rounding direction is enforced.
    /// @param outcomeSupply The current supply of the outcome.
    /// @param currentSumTerm36 The current sum of squared supplies (36 decimal precision).
    /// @return The implied probability (18 decimal fixed-point).
    function spotImpliedProbability(uint256 outcomeSupply, uint256 currentSumTerm36) internal pure returns (uint256) {
        // Note: This is only used in external views, so no need to round against the user
        return (outcomeSupply ** 2).mulDiv(1e18, currentSumTerm36);
    }

    /// @notice Calculates the number of shares per outcome minted at market creation.
    /// @dev Derivation:
    // price per share = k
    // total shares = shares per outcome * number of outcomes
    // initial deposit = price per share * total shares
    // initial deposit = k * shares per outcome * number of outcomes
    // shares per outcome = initial deposit / (k * number of outcomes)
    /// @param k The liquidity depth parameter.
    /// @param outcomeCount The number of outcomes.
    /// @param initialDeposit The initial deposit in token decimals.
    /// @param tokenDecimalScalar The token decimal scaler (10^(18-decimals)).
    /// @return The number of shares per outcome.
    function sharesPerOutcomeAtMarketCreation(
        uint256 k,
        uint256 outcomeCount,
        uint256 initialDeposit,
        uint256 tokenDecimalScalar
    ) internal pure returns (uint256) {
        return mulDivDown({a: initialDeposit * tokenDecimalScalar, b: 1e18, denominator: k * outcomeCount});
    }

    /// @notice Calculates the initial token pool size at market creation.

    /// @dev Derivation:
    // initialPool = k * sharesPerOutcome * sqrt(outcomeCount)
    // initialPool = k * sqrt(outcomeCount) * initialDeposit / (k * outcomeCount)
    // initialPool = initialDeposit * sqrt(outcomeCount) / outcomeCount
    // initialPool = initialDeposit / sqrt(outcomeCount)
    /// @param initialDeposit The initial deposit in token decimals.
    /// @param outcomeCount The number of outcomes.
    /// @return The initial pool size.
    function calculateInitialPool(uint256 initialDeposit, uint256 outcomeCount) internal pure returns (uint256) {
        return mulDivUp({a: initialDeposit, b: 1e18, denominator: sqrtDown(outcomeCount * 1e36)});
    }

    /// @param initialPool The initial pool size.
    /// @param outcomeCount The number of outcomes.
    /// @return The initial deposit in token decimals.
    function calculateInitialDeposit(uint256 initialPool, uint256 outcomeCount) internal pure returns (uint256) {
        return mulDivDown({a: initialPool, b: sqrtDown(outcomeCount * 1e36), denominator: 1e18});
    }

    /// @notice Calculates the token reward for a redeemer based on their share of winning outcome shares.
    /// @dev Rounded down (against the user).
    /// @param marketPool The total token pool available for redemptions.
    /// @param redeemerWinningShares The redeemer's winning shares.
    /// @param unclaimedShares The total unclaimed winning shares.
    /// @return The token reward.
    function redeemerReward(uint256 marketPool, uint256 redeemerWinningShares, uint256 unclaimedShares)
        internal
        pure
        returns (uint256)
    {
        return mulDivDown(marketPool, redeemerWinningShares, unclaimedShares); // Note: Down (against user)
    }

    /// @notice Calculates the token reward for a liquidator from an expired market.
    /// @dev Rounded down (against the user).
    /// @param k The liquidity depth parameter.
    /// @param numeratorSum Sum of (sharesIn_i * totalSupply_i) for each outcome, divided by 1e18.
    /// @param currentSumTerm36 The current sum of squared supplies (36 decimal precision).
    /// @param tokenDecimalScalar The token decimal scaler (10^(18-decimals)).
    /// @return The total token reward.
    function liquidatorTotalReward(
        uint256 k,
        uint256 numeratorSum,
        uint256 currentSumTerm36,
        uint256 tokenDecimalScalar
    ) internal pure returns (uint256) {
        uint256 denominator = sqrtUp(currentSumTerm36) * tokenDecimalScalar; // Note: Up (against user)
        return mulDivDown({a: k, b: numeratorSum, denominator: denominator}); // Note: Down (against user)
    }

    /// @notice Calculates the trading fees recipient's cut of accumulated fees.
    /// @dev Rounded down (against the recipient).
    /// @param tradingFees The total accumulated trading fees.
    /// @param tradingFeesRecipientPct The recipient's percentage (18 decimal fixed-point).
    /// @return The recipient's cut.
    function tradingFeesRecipientCut(uint256 tradingFees, uint256 tradingFeesRecipientPct)
        internal
        pure
        returns (uint256)
    {
        return mulDivDown(tradingFees, tradingFeesRecipientPct, 1e18); // Note: Down (against user)
    }

    // ===== MATH HELPERS =====

    /// @notice Computes the ceiling square root of a 36-decimal fixed-point number, returning an 18-decimal result.
    /// @param sqrtInput36 The input value (36 decimal precision).
    /// @return sqrtOutput18 The ceiling square root (18 decimal precision).
    function sqrtUp(uint256 sqrtInput36) internal pure returns (uint256 sqrtOutput18) {
        sqrtOutput18 = sqrtInput36.sqrt(Math.Rounding.Ceil);
    }

    /// @notice Computes the floor square root of a 36-decimal fixed-point number, returning an 18-decimal result.
    /// @param sqrtInput36 The input value (36 decimal precision).
    /// @return sqrtOutput18 The floor square root (18 decimal precision).
    function sqrtDown(uint256 sqrtInput36) internal pure returns (uint256 sqrtOutput18) {
        sqrtOutput18 = sqrtInput36.sqrt(Math.Rounding.Floor);
    }

    /// @notice Computes ceil(a * b / denominator).
    /// @param a The first factor.
    /// @param b The second factor.
    /// @param denominator The divisor.
    /// @return The result rounded up.
    function mulDivUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return a.mulDiv(b, denominator, Math.Rounding.Ceil);
    }

    /// @notice Computes floor(a * b / denominator).
    /// @param a The first factor.
    /// @param b The second factor.
    /// @param denominator The divisor.
    /// @return The result rounded down.
    function mulDivDown(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256) {
        return a.mulDiv(b, denominator, Math.Rounding.Floor);
    }
}
