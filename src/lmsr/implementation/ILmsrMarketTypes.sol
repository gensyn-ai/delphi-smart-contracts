// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ILmsrMarketTypes
/// @notice Shared structs and enums for the LMSR market (the on-chain <> off-chain data contract).
interface ILmsrMarketTypes {
    /// @notice The full state of a market.
    struct Market {
        MarketConfig config; // Market Config (specified by the Market Creator)
        uint256 pool; // Tokens backing outcome payouts (in token decimals); excludes fees and reserves
        uint256 tradingFees; // Accrued, undistributed trading fees (in token decimals)
        uint256 expSum; // Cached sum of all outcome exponents: sum of exp(q_i / b) (1e18 fixed-point)

        // Initialized to max uint256, this sentinel value signals that no winning outcome is set yet.
        // Can ONLY be set via the oracle path (oracle relayer -> gateway -> settleMarket) while the
        // market is AWAITING_SETTLEMENT. Setting this value transitions the market into the SETTLED status.
        uint256 winningOutcomeIdx;
    }

    /// @notice The immutable per-market configuration, chosen by the market creator at creation.
    struct MarketConfig {
        uint256 outcomeCount; // MIN_OUTCOME_COUNT (2) <= outcomeCount <= MAX_OUTCOME_COUNT
        uint256 b; // MIN_B <= b <= MAX_B
        uint256 tradingFee; // MIN_TRADING_FEE <= tradingFee <= MAX_TRADING_FEE
        uint256 tradingDeadline; // MIN_TRADING_WINDOW <= tradingDeadline - block.timestamp <= MAX_TRADING_WINDOW
        uint256 earliestResolveTime; // MIN_RESOLVE_DELAY <= earliestResolveTime - tradingDeadline <= MAX_RESOLVE_DELAY
        uint256 settlementDeadline; // MIN_SETTLEMENT_WINDOW <= settlementDeadline - earliestResolveTime <= MAX_SETTLEMENT_WINDOW
    }

    /// @notice The market lifecycle. Terminal states: SETTLED, EXPIRED (implicit, time-based), FAILED.
    enum MarketStatus {
        OPEN, // 0: Trading is open. Settlement cannot be requested yet.
        AWAITING_SETTLEMENT, // 1: Trading is closed. Resolution can be requested (keeper) only from earliestResolveTime; the oracle can then settle/fail.
        SETTLED, // 2: The oracle settled the market before `settlementDeadline`
        EXPIRED, // 3: The market was not settled before `settlementDeadline` (pro-rata liquidation)
        FAILED // 4: Oracle explicitly failed to resolve the market (terminal; pro-rata liquidation)
    }
}
