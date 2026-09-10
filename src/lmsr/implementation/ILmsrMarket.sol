// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IERC6909TokenSupply} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {ILmsrMarketTypes} from "./ILmsrMarketTypes.sol";
import {ILmsrMarketErrors} from "./ILmsrMarketErrors.sol";

/// @title ILmsrMarket
/// @notice Interface for an lmsr prediction market implemented via the ERC6909 standard.
/// @dev Markets follow a lifecycle: OPEN -> AWAITING_SETTLEMENT -> SETTLED, EXPIRED, or FAILED.
///      All LMSR state-transition functions are restricted to the gateway contract; the inherited
///      ERC-6909 share functions (transfer, transferFrom, approve, setOperator) are intentionally
///      permissionless (shares are freely transferable, except to the market itself).
interface ILmsrMarket is IERC6909TokenSupply, IDelphiMarket, ILmsrMarketTypes, ILmsrMarketErrors {
    // ===== EVENTS =====

    /// @notice Emitted when a user buys outcome shares.
    /// @param buyer The address of the buyer.
    /// @param outcomeIdx The index of the purchased outcome.
    /// @param tokensIn The amount of tokens spent.
    /// @param sharesOut The amount of outcome shares received.
    event Buy(address indexed buyer, uint256 indexed outcomeIdx, uint256 tokensIn, uint256 sharesOut);

    /// @notice Emitted when a user sells outcome shares.
    /// @param seller The address of the seller.
    /// @param outcomeIdx The index of the sold outcome.
    /// @param sharesIn The amount of outcome shares sold.
    /// @param tokensOut The amount of tokens received.
    event Sell(address indexed seller, uint256 indexed outcomeIdx, uint256 sharesIn, uint256 tokensOut);

    /// @notice Emitted when the market is settled with the winning outcome.
    /// @param winningOutcomeIdx The index of the winning outcome.
    /// @param losingPayout total amount of tokens rewarded from the losing outcomes
    /// @param tradingFeesRecipientTradingFeesCut the part of the trading fees that goes to the trading fees recipient
    /// @param marketCreatorTradingFeesCut the part of the trading fees that goes to the market creator
    event MarketSettled(
        uint256 winningOutcomeIdx,
        uint256 losingPayout,
        uint256 tradingFeesRecipientTradingFeesCut,
        uint256 marketCreatorTradingFeesCut
    );

    /// @notice Emitted when the market is failed.
    event MarketFailed();

    /// @notice Emitted when a user redeems winning shares for tokens.
    /// @param redeemer The address of the redeemer.
    /// @param winningSharesIn The amount of winning shares redeemed.
    /// @param tokensOut The amount of tokens received.
    event Redemption(address indexed redeemer, uint256 winningSharesIn, uint256 tokensOut);

    /// @notice Emitted when a user liquidates shares from an expired or failed market.
    /// @param liquidator The address of the liquidator.
    /// @param outcomeIndices The indices of the liquidated outcomes.
    /// @param sharesIn The amounts of shares liquidated per outcome.
    /// @param totalTokensOut The total amount of tokens received.
    event Liquidation(address indexed liquidator, uint256[] outcomeIndices, uint256[] sharesIn, uint256 totalTokensOut);

    /// @notice Emitted when accrued trading fees are swept on an expired/failed market.
    /// @param tradingFeesRecipientTradingFeesCut The part of the trading fees sent to the trading fees recipient.
    /// @param marketCreatorTradingFeesCut The part of the trading fees accrued to the market creator's claimable balance.
    event TradingFeesSwept(uint256 tradingFeesRecipientTradingFeesCut, uint256 marketCreatorTradingFeesCut);

    /// @notice Emitted when the losing payout of an expired/failed market is swept to the market creator.
    /// @param remainingPayout The pool remainder (after reserving all liquidation payouts) accrued to the creator.
    event LosingPayoutSwept(uint256 remainingPayout);

    /// @notice Emitted when the unpaid keeper fee of an expired/failed market is swept to the market creator.
    /// @param keeperFee The keeper fee amount (in token decimals).
    event KeeperFeeSwept(uint256 keeperFee);

    /// @notice Emitted when the unpaid oracle fee of an expired/failed market is swept to the market creator.
    /// @param oracleFee The oracle fee amount (in token decimals).
    event OracleFeeSwept(uint256 oracleFee);

    /// @notice Emitted when the market creator's reward is successfully transferred to them.
    /// @param marketCreatorReward The amount transferred (in token decimals).
    event MarketCreatorRewardTransferred(uint256 marketCreatorReward);

    // ===== CONSTANTS =====

    /// @notice Minimum number of outcomes a market can have.
    function MIN_OUTCOME_COUNT() external view returns (uint256);
    /// @notice Maximum number of outcomes a market can have.
    function MAX_OUTCOME_COUNT() external view returns (uint256);
    /// @notice Minimum liquidity depth parameter (b).
    function MIN_B() external view returns (uint256);
    /// @notice Maximum liquidity depth parameter (b).
    function MAX_B() external view returns (uint256);
    /// @notice Minimum trading fee percentage (18 decimal fixed-point).
    function MIN_TRADING_FEE() external view returns (uint256);
    /// @notice Maximum trading fee percentage (18 decimal fixed-point).
    function MAX_TRADING_FEE() external view returns (uint256);
    /// @notice Minimum trading window duration in seconds.
    function MIN_TRADING_WINDOW() external view returns (uint256);
    /// @notice Maximum trading window duration in seconds.
    function MAX_TRADING_WINDOW() external view returns (uint256);
    /// @notice Minimum resolve delay (earliestResolveTime - tradingDeadline) in seconds.
    function MIN_RESOLVE_DELAY() external view returns (uint256);
    /// @notice Maximum resolve delay (earliestResolveTime - tradingDeadline) in seconds.
    function MAX_RESOLVE_DELAY() external view returns (uint256);
    /// @notice Minimum settlement window duration in seconds.
    function MIN_SETTLEMENT_WINDOW() external view returns (uint256);
    /// @notice Maximum settlement window duration in seconds.
    function MAX_SETTLEMENT_WINDOW() external view returns (uint256);
    /// @notice Minimum percentage of trading fees that can go to the TRADING_FEES_RECIPIENT.
    function MIN_TRADING_FEES_RECIPIENT_PCT() external view returns (uint256);
    /// @notice Maximum percentage of trading fees that can go to the TRADING_FEES_RECIPIENT.
    function MAX_TRADING_FEES_RECIPIENT_PCT() external view returns (uint256);

    // ===== IMMUTABLES =====

    /// @notice The gateway contract which users must go through, in order to interact with this market.
    function GATEWAY() external view returns (address);
    /// @notice The address that receives TRADING_FEES_RECIPIENT_PCT of the trading fees (on settlement or sweep).
    function TRADING_FEES_RECIPIENT() external view returns (address);
    /// @notice The percentage of trading fees sent to the TRADING_FEES_RECIPIENT (18 decimal fixed-point).
    function TRADING_FEES_RECIPIENT_PCT() external view returns (uint256);
    /// @notice The decimal scaler for the token (10^(18-decimals)).
    function TOKEN_DECIMAL_SCALER() external view returns (uint256);
    /// @notice The fixed fee paid to the keeper that triggers oracle resolution (in token decimals).
    function KEEPER_FEE() external view returns (uint256);
    /// @notice The fixed fee reserved for the oracle network, consumed at settlement (in token decimals).
    function ORACLE_FEE() external view returns (uint256);

    // ===== INITIALIZATION IMMUTABLES =====

    /// @notice The address that created this market.
    function marketCreator() external view returns (address);

    // ===== EXTERNAL MUTATING FUNCTIONS =====

    /// @notice Transfers the keeper fee to the keeper. Only callable by the gateway.
    /// @dev Called before the oracle request is submitted so the transaction reverts early (before any
    ///      oracle-side effects) if the market is not in AWAITING_SETTLEMENT status. Also reverts with
    ///      CannotResolveMarketYet before `earliestResolveTime`, which gates the entire resolution flow:
    ///      trading close and resolution eligibility are deliberately separated by the resolve delay.
    /// @param keeper The address to receive the keeper fee.
    function transferKeeperFee(address keeper) external;

    /// @notice Transitions the market to FAILED status. Only callable by the gateway.
    /// @dev Only valid when market is in AWAITING_SETTLEMENT status.
    function failMarket() external;

    /// @notice Executes a buy of outcome shares. Only callable by the gateway.
    /// @param buyer The address buying shares.
    /// @param outcomeIdx The index of the outcome to buy.
    /// @param tokensIn The total tokens to spend (including fees).
    /// @param sharesOut The number of outcome shares to receive.
    function buy(address buyer, uint256 outcomeIdx, uint256 tokensIn, uint256 sharesOut) external;

    /// @notice Executes a sell of outcome shares. Only callable by the gateway.
    /// @param seller The address selling shares.
    /// @param outcomeIdx The index of the outcome to sell.
    /// @param sharesIn The number of outcome shares to sell.
    /// @param tokensOut The tokens to receive (after fees).
    function sell(address seller, uint256 outcomeIdx, uint256 sharesIn, uint256 tokensOut) external;

    /// @notice Settles the market with the winning outcome, distributes fees and creator rewards, and
    ///         transfers the oracle fee to the recipient. Only callable by the gateway.
    /// @param winningOutcomeIdx The index of the winning outcome.
    /// @param oracleFeeRecipient The address to receive the oracle fee (e.g. oracle treasury). Pass-through.
    function settleMarket(uint256 winningOutcomeIdx, address oracleFeeRecipient)
        external
        returns (uint256 losingPayout, uint256 tradingFeesRecipientTradingFeesCut, uint256 marketCreatorTradingFeesCut);

    /// @notice Redeems a user's winning outcome shares for tokens. Only callable by the gateway.
    /// @param redeemer The address redeeming shares.
    /// @return sharesIn The number of winning shares redeemed.
    /// @return tokensOut The number of tokens received.
    function redeem(address redeemer) external returns (uint256 sharesIn, uint256 tokensOut);

    /// @notice Liquidates a user's shares from an expired or failed market. Only callable by the gateway.
    /// @dev Values every liquidated share at the outcome's frozen final LMSR marginal price. Because a
    ///      position's average acquisition cost is always below its final marginal price, a trader who
    ///      raises an outcome's price before an anticipated FAILED/EXPIRED terminal state can liquidate
    ///      for more than they paid; the difference is drawn from the market creator's subsidy (the pool
    ///      stays solvent). This terminal-price manipulation risk is accepted for now — see the
    ///      "Terminal-price liquidation risk" section in AGENTS.md.
    /// @param liquidator The address liquidating shares.
    /// @param outcomeIndices The indices of outcomes to liquidate.
    /// @return sharesIn The amounts of shares liquidated per outcome.
    /// @return totalTokensOut The total number of tokens received.
    function liquidate(address liquidator, uint256[] calldata outcomeIndices)
        external
        returns (uint256[] memory sharesIn, uint256 totalTokensOut);

    /// @notice Sweeps claimable rewards (trading fees, losing payout, unpaid keeper/oracle fees) if the
    ///         market is EXPIRED or FAILED, and retries the market creator's pending claimable transfer
    ///         in any status. Only callable by the gateway.
    function trySweep() external;

    // ===== EXTERNAL VIEWS =====

    // Market Info

    /// @return market The full market struct including configuration and state.
    function getMarket() external view returns (Market memory market);

    /// @return True if `outcomeIdx` is within the configured outcome range, false otherwise.
    function isValidOutcomeIdx(uint256 outcomeIdx) external view returns (bool);

    /// @return The current lifecycle status of the market.
    function marketStatus() external view returns (MarketStatus);

    // Spot Price
    // Note: The price views are status-dependent. Consumers must interpret them together with marketStatus():
    // - OPEN / AWAITING_SETTLEMENT: the live LMSR marginal price (frozen at its closing value once trading ends).
    // - SETTLED: the claim value — one whole token per whole share (1e18 / TOKEN_DECIMAL_SCALER) for the
    //   winning outcome, zero for every losing outcome.
    // - EXPIRED / FAILED: the frozen LMSR closing price, which is exactly what liquidation pays out.

    /// @param outcomeIdx The index of the outcome.
    /// @return The spot price of the given outcome (in token decimals per whole share; status-dependent, see above).
    function spotPrice(uint256 outcomeIdx) external view returns (uint256);

    /// @param outcomeIndices The indices of the outcomes.
    /// @return The spot prices for the given outcomes (status-dependent, see above).
    function spotPrices(uint256[] calldata outcomeIndices) external view returns (uint256[] memory);

    // Spot Probability
    // Note: Status-dependent like the price views: LMSR implied probability while unsettled or
    // expired/failed (frozen at close), and 1e18 for the winning outcome / 0 for losers once SETTLED.

    /// @param outcomeIdx The index of the outcome.
    /// @return The spot implied probability of the given outcome (1e18 fixed-point; status-dependent, see above).
    function spotImpliedProbability(uint256 outcomeIdx) external view returns (uint256);

    /// @param outcomeIndices The indices of the outcomes.
    /// @return The spot implied probabilities for the given outcomes (status-dependent, see above).
    function spotImpliedProbabilities(uint256[] calldata outcomeIndices) external view returns (uint256[] memory);

    // Supplies

    /// @param outcomeIndices The indices of the outcomes.
    /// @return The total supplies for the given outcomes.
    function totalSupplies(uint256[] calldata outcomeIndices) external view returns (uint256[] memory);

    // Balances

    /// @param owners The addresses of the owners.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The share balances for the given owner-outcome pairs.
    function batchBalanceOf(address[] calldata owners, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    /// @return The Unix timestamp when this market was created.
    function createdAt() external view returns (uint256);

    /// @return Whether the market has been explicitly failed by the oracle relayer.
    function marketFailed() external view returns (bool);

    /// @return Whether the keeper fee has been disbursed
    function keeperFeePaid() external view returns (bool);

    /// @return Whether the oracle fee has been disbursed.
    function oracleFeePaid() external view returns (bool);

    /// @return Whether the losing payout has been swept.
    function losingPayoutSwept() external view returns (bool);

    /// @return The amount of market creator rewards that can be claimed.
    function marketCreatorClaimable() external view returns (uint256);
}
