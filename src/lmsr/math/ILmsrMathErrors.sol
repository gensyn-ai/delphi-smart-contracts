// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ILmsrMathErrors
/// @notice Errors thrown by the LmsrMath library (and bubbled up through the market and gateway).
interface ILmsrMathErrors {
    /// @notice Thrown when an exp input exceeds MAX_EXP_INPUT.
    /// @param expInput The provided exp input (1e18 fixed-point).
    /// @param maxExpInput The maximum allowed exp input (MAX_EXP_INPUT).
    error ExpInputTooBig(uint256 expInput, uint256 maxExpInput);

    /// @notice Thrown when validating a buy with zero tokens in.
    error ZeroTokensIn();

    /// @notice Thrown when validating a buy with zero shares out.
    error ZeroSharesOut();

    /// @notice Thrown when a buy is too small to be priced without excessive precision loss.
    error BuyTooSmall();

    /// @notice Thrown when validating a sell (or liquidation) with zero shares in.
    error ZeroSharesIn();

    /// @notice Thrown when selling more shares than the outcome's current supply.
    /// @param sharesIn The number of shares being sold.
    /// @param supply The outcome's current supply.
    error SharesInExceedSupply(uint256 sharesIn, uint256 supply);

    /// @notice Thrown when validating a sell with zero tokens out.
    error ZeroTokensOut();

    /// @notice Thrown when a sell is too small to be priced without excessive precision loss.
    error SellTooSmall();

    /// @notice Thrown when a ln result is too small to subtract the conservative error bound from.
    error LnInputTooSmall();

    /// @notice Thrown when an exp-sum ratio truncates to <= 1 (trade too small to price).
    error RatioTooSmall();
}
