// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IDynamicParimutuelMarketTypes {
    struct Market {
        MarketConfig config; // Market Config (specified by the Market Creator)
        uint256 pool;
        uint256 tradingFees;
        uint256 sumTerm36; // supply(outcome1)^2 + supply(outcome2)^2 + ... + supply(outcomeN)^2

        // Initialized to max uint256, this sentinel value signals that no winning outcome is set yet.
        // Can ONLY be set by the creator while the market is AWAITING_SETTLEMENT.
        // Setting this value will transition the market into the SETTLED status.
        uint256 winningOutcomeIdx;
    }

    struct MarketConfig {
        uint256 outcomeCount; // MIN_OUTCOME_COUNT (2) <= outcomeCount <= MAX_OUTCOME_COUNT
        uint256 k; // MIN_K <= k <= MAX_K
        uint256 tradingFee; // MIN_TRADING_FEE <= k <= MAX_TRADING_FEE
        uint256 tradingDeadline; // MIN_TRADING_WINDOW <= tradingDeadline - block.timestamp <= MAX_TRADING_WINDOW
        uint256 settlementDeadline; // MIN_SETTLEMENT_WINDOW <= settlementDeadline - tradingDeadline <= MAX_SETTLEMENT_WINDOW
    }

    enum MarketStatus {
        OPEN, // 0: Trading is open. Market Creator cannot settle.
        AWAITING_SETTLEMENT, // 1: Trading is closed. Market Creator can settle
        SETTLED, // 2: If Market Creator settles before `settlementDeadline`
        EXPIRED // 3: If Market Creator does not settle before `settlementDeadline`
    }
}
