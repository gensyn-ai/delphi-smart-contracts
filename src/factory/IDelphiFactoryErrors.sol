// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IDelphiFactoryErrors
/// @notice Errors thrown by the DelphiFactory contract.
interface IDelphiFactoryErrors {
    // ===== CONSTRUCTOR =====

    /// @notice Thrown when the market implementation address is the zero address.
    error ImplementationIsZeroAddress();

    /// @notice Thrown when the market implementation address has no code.
    /// @param implementation The provided implementation address.
    error ImplementationIsNotAContract(address implementation);

    /// @notice Thrown when the market creation fee is below the minimum.
    /// @param provided The provided market creation fee (in token decimals).
    /// @param minimum The minimum allowed market creation fee (in token decimals).
    error MarketCreationFeeIsTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown when the market creation fee is above the maximum.
    /// @param provided The provided market creation fee (in token decimals).
    /// @param maximum The maximum allowed market creation fee (in token decimals).
    error MarketCreationFeeIsTooHigh(uint256 provided, uint256 maximum);

    /// @notice Thrown when the market creation fee recipient is the zero address.
    error MarketCreationFeeRecipientIsZeroAddress();

    /// @notice Thrown when the implementation's settlement fees (keeper + oracle) exceed the market creation fee.
    /// @param settlementFees The implementation's KEEPER_FEE + ORACLE_FEE (in token decimals).
    /// @param marketCreationFee The provided market creation fee (in token decimals).
    error SettlementFeesExceedMarketCreationFee(uint256 settlementFees, uint256 marketCreationFee);

    // ===== GET MARKET PROXIES =====

    /// @notice Thrown when a market proxy range query has firstIdx > lastIdx.
    /// @param firstIdx The provided first index (inclusive).
    /// @param lastIdx The provided last index (inclusive).
    error FirstIdxExceedsLastIdx(uint256 firstIdx, uint256 lastIdx);

    /// @notice Thrown when a market proxy range query exceeds the number of deployed markets.
    /// @param lastIdx The provided last index (inclusive).
    /// @param marketCount The total number of deployed market proxies.
    error LastIdxOutOfBounds(uint256 lastIdx, uint256 marketCount);
}
