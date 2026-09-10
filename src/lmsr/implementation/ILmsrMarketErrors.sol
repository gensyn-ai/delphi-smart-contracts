// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {ILmsrMarketTypes} from "./ILmsrMarketTypes.sol";
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";

/// @title ILmsrMarketErrors
/// @notice Errors thrown by the LmsrMarket contract.
interface ILmsrMarketErrors is ILmsrMarketTypes, ILmsrMathErrors {
    // ===== CONSTRUCTOR =====

    /// @notice Thrown when the trading fees recipient is the zero address.
    error TradingFeesRecipientIsZeroAddress();

    /// @notice Thrown when the gateway address is the zero address.
    error GatewayIsZeroAddress();

    /// @notice Thrown when the trading fees recipient pct is below the minimum.
    /// @param provided The provided pct (18 decimal fixed-point).
    /// @param minimum The minimum allowed pct (MIN_TRADING_FEES_RECIPIENT_PCT).
    error TradingFeesRecipientPctIsTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown when the trading fees recipient pct is above the maximum.
    /// @param provided The provided pct (18 decimal fixed-point).
    /// @param maximum The maximum allowed pct (MAX_TRADING_FEES_RECIPIENT_PCT).
    error TradingFeesRecipientPctIsTooHigh(uint256 provided, uint256 maximum);

    // ===== INITIALIZER =====

    // Market Creator

    /// @notice Thrown when the market creator is the zero address.
    error MarketCreatorIsZeroAddress();

    // Gateway

    /// @notice Thrown when creating a market while the gateway has no oracle relayer wired.
    error GatewayOracleRelayerNotSet();

    // Lmsr Config

    /// @notice Thrown when the outcome count is below the minimum.
    /// @param provided The provided outcome count.
    /// @param minimum The minimum allowed outcome count (MIN_OUTCOME_COUNT).
    error OutcomeCountIsTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown when the outcome count is above the maximum.
    /// @param provided The provided outcome count.
    /// @param maximum The maximum allowed outcome count (MAX_OUTCOME_COUNT).
    error OutcomeCountIsTooHigh(uint256 provided, uint256 maximum);

    /// @notice Thrown when the liquidity parameter b is below the minimum.
    /// @param provided The provided b (18 decimal fixed-point).
    /// @param minimum The minimum allowed b (MIN_B).
    error BIsTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown when the liquidity parameter b is above the maximum.
    /// @param provided The provided b (18 decimal fixed-point).
    /// @param maximum The maximum allowed b (MAX_B).
    error BIsTooHigh(uint256 provided, uint256 maximum);

    /// @notice Thrown when the trading fee is below the minimum.
    /// @param provided The provided trading fee (18 decimal fixed-point).
    /// @param minimum The minimum allowed trading fee (MIN_TRADING_FEE).
    error TradingFeeIsTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown when the trading fee is above the maximum.
    /// @param provided The provided trading fee (18 decimal fixed-point).
    /// @param maximum The maximum allowed trading fee (MAX_TRADING_FEE).
    error TradingFeeIsTooHigh(uint256 provided, uint256 maximum);

    /// @notice Thrown when the trading deadline is not in the future.
    /// @param provided The provided trading deadline (Unix timestamp).
    /// @param currentTimestamp The current block timestamp.
    error TradingDeadlineIsNotInTheFuture(uint256 provided, uint256 currentTimestamp);

    /// @notice Thrown when the trading window is below the minimum.
    /// @param provided The provided trading window (seconds).
    /// @param minimum The minimum allowed trading window (MIN_TRADING_WINDOW).
    error TradingWindowIsTooShort(uint256 provided, uint256 minimum);

    /// @notice Thrown when the trading window is above the maximum.
    /// @param provided The provided trading window (seconds).
    /// @param maximum The maximum allowed trading window (MAX_TRADING_WINDOW).
    error TradingWindowIsTooLong(uint256 provided, uint256 maximum);

    /// @notice Thrown when the earliest resolve time is not after the trading deadline.
    /// @param earliestResolveTime The provided earliest resolve time (Unix timestamp).
    /// @param tradingDeadline The provided trading deadline (Unix timestamp).
    error EarliestResolveTimeIsNotAfterTheTradingDeadline(uint256 earliestResolveTime, uint256 tradingDeadline);

    /// @notice Thrown when the resolve delay (earliestResolveTime - tradingDeadline) is below the minimum.
    /// @param provided The provided resolve delay (seconds).
    /// @param minimum The minimum allowed resolve delay (MIN_RESOLVE_DELAY).
    error ResolveDelayIsTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown when the resolve delay (earliestResolveTime - tradingDeadline) is above the maximum.
    /// @param provided The provided resolve delay (seconds).
    /// @param maximum The maximum allowed resolve delay (MAX_RESOLVE_DELAY).
    error ResolveDelayIsTooHigh(uint256 provided, uint256 maximum);

    /// @notice Thrown when the settlement deadline is not after the earliest resolve time.
    /// @param settlementDeadline The provided settlement deadline (Unix timestamp).
    /// @param earliestResolveTime The provided earliest resolve time (Unix timestamp).
    error SettlementDeadlineIsNotAfterTheEarliestResolveTime(uint256 settlementDeadline, uint256 earliestResolveTime);

    /// @notice Thrown when the settlement window is below the minimum.
    /// @param provided The provided settlement window (seconds).
    /// @param minimum The minimum allowed settlement window (MIN_SETTLEMENT_WINDOW).
    error SettlementWindowIsTooShort(uint256 provided, uint256 minimum);

    /// @notice Thrown when the settlement window is above the maximum.
    /// @param provided The provided settlement window (seconds).
    /// @param maximum The maximum allowed settlement window (MAX_SETTLEMENT_WINDOW).
    error SettlementWindowIsTooLong(uint256 provided, uint256 maximum);

    // Verifiable Uri

    /// @notice Thrown when the market metadata URI is empty.
    error UriIsEmpty();

    /// @notice Thrown when the market metadata URI content hash is zero.
    error UriContentHashIsZero();

    // Token Balance

    /// @notice Thrown when the initial deposit does not cover the market's maximum possible loss.
    /// @param balance The market's token balance at initialization (in token decimals).
    /// @param maxLoss The required minimum, b * ln(outcomeCount) (in token decimals).
    error TokenBalanceIsLessThanMaxLoss(uint256 balance, uint256 maxLoss);

    // ===== BUY =====

    /// @notice Thrown when a buy fails economic validation (tokens in do not cover the LMSR cost).
    error InvalidBuy();

    // ===== SELL =====

    /// @notice Thrown when the gross tokens out (incl. fee) exceed the market pool.
    /// @param grossTokensOut The gross tokens out (in token decimals).
    /// @param marketPool The current market pool (in token decimals).
    error GrossTokensOutExceedMarketPool(uint256 grossTokensOut, uint256 marketPool);

    /// @notice Thrown when a sell fails economic validation (tokens out exceed the LMSR cost reduction).
    error InvalidSell();

    // ===== TRANSFER KEEPER FEE =====

    /// @notice Thrown when the keeper fee has already been paid.
    error KeeperFeeAlreadyPaid();

    /// @notice Thrown when resolution is requested before the market's earliest resolve time.
    /// @param currentTime The current block timestamp.
    /// @param earliestResolveTime The earliest timestamp at which resolution may be requested.
    error CannotResolveMarketYet(uint256 currentTime, uint256 earliestResolveTime);

    // ===== REDEEM =====

    /// @notice Thrown when the redeemer's winning shares are too few to be worth at least one token unit.
    /// @param winningSharesIn The redeemer's winning shares (18 decimals).
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    error WinningSharesInAreLessThanTokenDecimalScaler(uint256 winningSharesIn, uint256 tokenDecimalScaler);

    // ===== LIQUIDATE/TRY SWEEP =====

    /// @notice Thrown when the market is neither EXPIRED nor FAILED.
    /// @param current The market's current status.
    error MarketNotExpiredNorFailed(MarketStatus current);

    // ===== LIQUIDATE =====

    /// @notice Thrown when a liquidation would pay out zero tokens.
    /// @param numeratorSum36 The liquidation numerator, sum of sharesIn_i * outcomeExp_i (36 decimals).
    /// @param expSum The market's current exp sum (18 decimals).
    /// @param tokenDecimalScaler The token decimal scaler (10^(18-decimals)).
    error TotalTokensOutIsZero(uint256 numeratorSum36, uint256 expSum, uint256 tokenDecimalScaler);

    /// @notice Thrown when liquidating with an empty outcome indices array.
    error OutcomeIndicesAreEmpty();

    // ===== TRANSFER =====

    /// @notice Thrown when transferring outcome shares to the market itself.
    error CannotTransferSharesToMarket();

    // ===== BATCH BALANCE OF =====

    /// @notice Thrown when the owners and outcome indices arrays have different lengths.
    /// @param ownersLength The length of the owners array.
    /// @param indicesLength The length of the outcome indices array.
    error ArrayLengthMismatch(uint256 ownersLength, uint256 indicesLength);

    // ===== ONLY GATEWAY =====

    /// @notice Thrown when the caller is not the gateway.
    /// @param caller The caller.
    error CallerIsNotGateway(address caller);

    // ===== VALID OUTCOME INDEX =====

    /// @notice Thrown when an outcome index is out of bounds for the market.
    /// @param provided The provided outcome index.
    /// @param outcomeCount The market's outcome count.
    error OutcomeIsOutOfBounds(uint256 provided, uint256 outcomeCount);

    // ===== IF STATUS =====

    /// @notice Thrown when the market is not in the required status.
    /// @param current The market's current status.
    /// @param required The required status.
    error WrongMarketStatus(MarketStatus current, MarketStatus required);
}
