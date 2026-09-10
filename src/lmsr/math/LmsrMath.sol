// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Libraries
import {LogExpMath} from "lib/balancer-v3-monorepo/pkg/solidity-utils/contracts/math/LogExpMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Errors
import {ILmsrMathErrors} from "./ILmsrMathErrors.sol";

/// @title LmsrMath
/// @notice Library implementing the mathematical operations for LMSR Prediction Markets.
/// @dev All rounding is performed against the user (tokensIn rounded up, tokensOut rounded down) to prevent value extraction.
library LmsrMath {
    // ===== CONSTANTS =====

    /// @notice Maximum input accepted by _computeExp (1e18 fixed-point).
    uint256 public constant MAX_EXP_INPUT = 30e18;

    /// @dev Conservative relative error for exp calculations.
    uint256 internal constant _MAX_EXP_REL_ERROR = 1000; // 1e-15

    /// @dev Conservative absolute error for ln calculations.
    uint256 internal constant _MAX_LN_ABS_ERROR = 100;

    /// @dev Fixed-point scaler (1e18).
    uint256 internal constant _ONE = 1e18;

    // ===== LIBRARIES =====
    using LogExpMath for int256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @notice Validates that a buy is economically sound: the tokens paid cover the cost of the shares minted.
    /// @param b The liquidity parameter.
    /// @param currentExpSum The current sum of outcome exponents.
    /// @param outcomeCurrentSupply The current supply of the outcome being bought.
    /// @param tokensIn The net tokens in (after fees).
    /// @param sharesOut The number of shares to receive.
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    /// @return newExpSum The updated sum term after the buy.
    /// @return valid True if the buy is economically valid.
    function buyIsValid(
        uint256 b,
        uint256 currentExpSum,
        uint256 outcomeCurrentSupply,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 tokenDecimalScaler
    ) internal pure returns (uint256 newExpSum, bool valid) {
        // Checks: Validate tokens in
        if (tokensIn == 0) {
            revert ILmsrMathErrors.ZeroTokensIn();
        }

        // Checks: Validate shares out
        if (sharesOut == 0) {
            revert ILmsrMathErrors.ZeroSharesOut();
        }

        // Calculate exps
        // Note: No rounding, to not propagate error to future trades
        uint256 outcomeNewExp = outcomeExp(b, outcomeCurrentSupply + sharesOut);
        uint256 outcomeCurrentExp = outcomeExp(b, outcomeCurrentSupply);

        // Checks: Calculate and Validate new exp sum
        newExpSum = currentExpSum + outcomeNewExp - outcomeCurrentExp;
        assert(newExpSum > currentExpSum);

        // Checks: Calculate and Validate exp sum bounds
        uint256 newExpSumUpperBound = getExpUpperBound(newExpSum); // Note: Up (against user)
        uint256 currentExpSumLowerBound = getExpLowerBound(currentExpSum); // Note: Down (against user)
        assert(newExpSumUpperBound > currentExpSumLowerBound);

        // Checks: Calculate & Validate ratio, rounded against user (up)
        uint256 ratio = newExpSumUpperBound.mulDiv(1e18, currentExpSumLowerBound, Math.Rounding.Ceil);
        assert(ratio > 1e18);

        // Calculate ln of ratio, rounded against user (up)
        uint256 ratioLnUpperBound = computeLnUpperBound(ratio);

        // Check if buy is valid
        valid = tokensIn * tokenDecimalScaler * 1e18 >= b * ratioLnUpperBound;
    }

    /// @notice Validates that a sell is economically sound: the tokens received do not exceed the cost reduction.
    /// @param b The liquidity parameter.
    /// @param currentExpSum The current sum of outcome exponents.
    /// @param outcomeCurrentSupply The current supply of the outcome being sold.
    /// @param sharesIn The number of shares to sell.
    /// @param tokensOut The gross tokens out.
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    /// @return newExpSum The updated sum term after the sell.
    /// @return valid True if the sell is economically valid.
    function sellIsValid(
        uint256 b,
        uint256 currentExpSum,
        uint256 outcomeCurrentSupply,
        uint256 sharesIn,
        uint256 tokensOut,
        uint256 tokenDecimalScaler
    ) internal pure returns (uint256 newExpSum, bool valid) {
        // Checks: Validate shares in
        if (sharesIn == 0) {
            revert ILmsrMathErrors.ZeroSharesIn();
        }
        if (sharesIn > outcomeCurrentSupply) {
            revert ILmsrMathErrors.SharesInExceedSupply(sharesIn, outcomeCurrentSupply);
        }

        // Checks: Validate tokens out
        if (tokensOut == 0) {
            revert ILmsrMathErrors.ZeroTokensOut();
        }

        // Calculate exps
        // Note: No rounding, to not propagate error to future trades
        uint256 outcomeNewExp = outcomeExp(b, outcomeCurrentSupply - sharesIn);
        uint256 outcomeCurrentExp = outcomeExp(b, outcomeCurrentSupply);

        // Checks: Calculate and Validate new exp sum
        newExpSum = currentExpSum + outcomeNewExp - outcomeCurrentExp;
        assert(newExpSum < currentExpSum);

        // Checks: Calculate and Validate exp sum bounds
        uint256 currentExpSumLowerBound = getExpLowerBound(currentExpSum); // Note: Down (against user)
        uint256 newExpSumUpperBound = getExpUpperBound(newExpSum); // Note: Up (against user)
        if (newExpSumUpperBound >= currentExpSumLowerBound) {
            revert ILmsrMathErrors.SellTooSmall();
        }

        // Checks: Calculate & Validate ratio, rounded against user (down)
        uint256 ratio = currentExpSumLowerBound.mulDiv(1e18, newExpSumUpperBound, Math.Rounding.Floor);
        assert(ratio > 1e18);

        // Calculate ln of ratio, rounded against user (down)
        uint256 ratioLnLowerBound = computeLnLowerBound(ratio);

        // Check if sell is valid
        valid = tokensOut * tokenDecimalScaler * 1e18 <= b * ratioLnLowerBound;
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
        grossAmount = netAmount.mulDiv(1e18, 1e18 - tradingFee, Math.Rounding.Ceil); // Note: Up (against user)
        feeAmount = grossAmount - netAmount;
    }

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
        netAmount = grossAmount.mulDiv(1e18 - tradingFee, 1e18, Math.Rounding.Floor); // Note: Down (against user)
        feeAmount = grossAmount - netAmount;
    }

    /// @notice Computes an outcome's exponent term: exp(outcomeSupply / b).
    /// @param b The liquidity parameter (18 decimal fixed-point).
    /// @param outcomeSupply The outcome's share supply (18 decimals).
    /// @return exp(outcomeSupply / b) in 1e18 fixed-point.
    /// @custom:reverts ExpInputTooBig If outcomeSupply / b > MAX_EXP_INPUT.
    function outcomeExp(uint256 b, uint256 outcomeSupply) internal pure returns (uint256) {
        return _computeExp(outcomeSupply.mulDiv(1e18, b));
    }

    /// @notice Calculates the spot price of a specific outcome.
    /// @dev Only used in external views, so no rounding direction is enforced.
    /// @param b The liquidity parameter.
    /// @param outcomeSupply The current supply of the outcome.
    /// @param marketExp The current market exponent.
    /// @return The spot price of the outcome.
    function spotPrice(uint256 b, uint256 outcomeSupply, uint256 marketExp, uint256 tokenDecimalScaler)
        internal
        pure
        returns (uint256)
    {
        // Note: This is only used in external views, so no need to round against the user
        return spotImpliedProbability(b, outcomeSupply, marketExp) / tokenDecimalScaler;
    }

    /// @notice Calculates the spot implied probability of a specific outcome.
    /// @dev Only used in external views, so no rounding direction is enforced.
    /// @param outcomeSupply The current supply of the outcome.
    /// @param marketExp The current market exponent.
    /// @return The implied probability (18 decimal fixed-point).
    function spotImpliedProbability(uint256 b, uint256 outcomeSupply, uint256 marketExp)
        internal
        pure
        returns (uint256)
    {
        // Note: This is only used in external views, so no need to round against the user
        return outcomeExp(b, outcomeSupply).mulDiv(1e18, marketExp);
    }

    /// @notice Computes the maximum possible loss of a market: b * ln(outcomeCount).
    /// @dev Rounded up (against the Market Creator), so the required deposit always covers the true loss.
    /// @param b The liquidity parameter (18 decimal fixed-point).
    /// @param outcomeCount The number of outcomes.
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    /// @return The maximum loss, in token decimals.
    function maxLoss(uint256 b, uint256 outcomeCount, uint256 tokenDecimalScaler) internal pure returns (uint256) {
        return b.mulDiv(computeLnUpperBound(outcomeCount * 1e18), 1e18 * tokenDecimalScaler, Math.Rounding.Ceil);
    }

    /// @notice Calculates the token reward for a redeemer based on their share of winning outcome shares.
    /// @dev Rounded down (against the user).
    /// @param winningSharesIn The redeemer's winning shares.
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    /// @return The token reward.
    function redeemerReward(uint256 winningSharesIn, uint256 tokenDecimalScaler) internal pure returns (uint256) {
        return winningSharesIn / tokenDecimalScaler; // Note: Down (against user)
    }

    /// @notice Calculates the token reward for a liquidator from an expired or failed market.
    /// @dev Rounded down (against the user). Values every share at the outcome's frozen final LMSR
    ///      marginal price, which is strictly above the position's average acquisition cost — a known,
    ///      accepted terminal-price manipulation risk funded by the market creator's subsidy (the pool
    ///      stays solvent). See the "Terminal-price liquidation risk" section in AGENTS.md.
    /// @param numeratorSum36 Sum of (sharesIn_i * outcomeExp_i) for each outcome.
    /// @param currentExpSum The current sum of all outcome exponents.
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    /// @return The total token reward.
    /* Note:
     * totalTokensOut = (outcome1SharesIn * outcome1SpotPrice) + ... + (outcomeNSharesIn * outcomeNSpotPrice)
     * totalTokensOut = (outcome1SharesIn * outcome1Exp / expSum) + ... + (outcomeNSharesIn * outcomeNExp / expSum)
     * totalTokensOut = ((outcome1SharesIn * outcome1Exp) + ... + (outcomeNSharesIn * outcomeNExp)) / expSum
     */
    function liquidatorTotalReward(uint256 numeratorSum36, uint256 currentExpSum, uint256 tokenDecimalScaler)
        internal
        pure
        returns (uint256)
    {
        return numeratorSum36 / (currentExpSum * tokenDecimalScaler); // Note: Down (against user)
    }

    /// @notice Calculates the trading fees recipient's cut of accumulated fees.
    /// @dev Rounded up (against the Market Creator).
    /// @param tradingFees The total accumulated trading fees.
    /// @param tradingFeesRecipientPct The recipient's percentage (18 decimal fixed-point).
    /// @return The recipient's cut.
    function tradingFeesRecipientCut(uint256 tradingFees, uint256 tradingFeesRecipientPct)
        internal
        pure
        returns (uint256)
    {
        return tradingFees.mulDiv(tradingFeesRecipientPct, 1e18, Math.Rounding.Ceil); // Note: Up (against Market Creator)
    }

    // ===== MATH HELPERS =====

    /// @dev Returns a conservative upper bound for a precomputed exp.
    /// @param exp The precomputed exp to adjust (1e18 fixed-point).
    /// @return Upper bound according to _MAX_EXP_REL_ERROR.
    function getExpUpperBound(uint256 exp) internal pure returns (uint256) {
        return exp + exp.mulDiv(_MAX_EXP_REL_ERROR, _ONE, Math.Rounding.Ceil);
    }

    /// @dev Returns a conservative lower bound for a precomputed exp.
    /// @param exp The precomputed exp to adjust (1e18 fixed-point).
    /// @return Lower bound according to _MAX_EXP_REL_ERROR.
    function getExpLowerBound(uint256 exp) internal pure returns (uint256) {
        return exp - exp.mulDiv(_MAX_EXP_REL_ERROR, _ONE, Math.Rounding.Ceil);
    }

    /// @dev Computes ln(x), and adjusts it to a conservative upper bound.
    /// @param lnInput Natural log input (1e18 fixed-point, must be >= 1e18).
    /// @return Upper bound according to _MAX_LN_ABS_ERROR.
    function computeLnUpperBound(uint256 lnInput) internal pure returns (uint256) {
        return _computeLn(lnInput) + _MAX_LN_ABS_ERROR;
    }

    /// @dev Computes ln(x), and adjusts it to a conservative lower bound.
    /// @param lnInput Natural log input (1e18 fixed-point, must be >= 1e18).
    /// @return Lower bound according to _MAX_LN_ABS_ERROR.
    function computeLnLowerBound(uint256 lnInput) internal pure returns (uint256) {
        uint256 ln = _computeLn(lnInput);
        if (ln < _MAX_LN_ABS_ERROR) {
            revert ILmsrMathErrors.LnInputTooSmall();
        }
        return ln - _MAX_LN_ABS_ERROR;
    }

    /// @dev Computes exp(x) for 1e18 fixed-point inputs.
    /// @param expInput Exponent input (1e18 fixed-point).
    /// @return exp(expInput) in 1e18 fixed-point.
    /// @custom:reverts ExpInputTooBig If expInput > MAX_EXP_INPUT.
    function _computeExp(uint256 expInput) private pure returns (uint256) {
        if (expInput > MAX_EXP_INPUT) {
            revert ILmsrMathErrors.ExpInputTooBig(expInput, MAX_EXP_INPUT);
        }
        return expInput.toInt256().exp().toUint256();
    }

    /// @dev Computes ln(x) using Balancer's fixed-point math.
    /// @param lnInput Natural log input (1e18 fixed-point, must be > 1e18).
    /// @return ln(lnInput) in 1e18 fixed-point.
    function _computeLn(uint256 lnInput) private pure returns (uint256) {
        return lnInput.toInt256().ln().toUint256();
    }
}
