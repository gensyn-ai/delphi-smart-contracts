// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IERC6909TokenSupply} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarketTypes} from "./IDynamicParimutuelMarketTypes.sol";
import {IDynamicParimutuelMarketErrors} from "./IDynamicParimutuelMarketErrors.sol";

/// @title IDynamicParimutuelMarket
/// @notice Interface for a dynamic parimutuel prediction market implemented via the ERC6909 standard.
/// @dev Markets follow a lifecycle: OPEN -> AWAITING_SETTLEMENT -> SETTLED or EXPIRED.
///      All mutating functions are restricted to the gateway contract.
interface IDynamicParimutuelMarket is
    IERC6909TokenSupply,
    IDelphiMarket,
    IDynamicParimutuelMarketTypes,
    IDynamicParimutuelMarketErrors
{
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

    /// @notice Emitted when the market creator submits the winning outcome.
    /// @param winningOutcomeIdx The index of the winning outcome.
    event WinnerSubmitted(uint256 winningOutcomeIdx);

    /// @notice Emitted when a user redeems winning shares for tokens.
    /// @param redeemer The address of the redeemer.
    /// @param sharesIn The amount of winning shares redeemed.
    /// @param tokensOut The amount of tokens received.
    event Redemption(address indexed redeemer, uint256 sharesIn, uint256 tokensOut);

    /// @notice Emitted when a user liquidates shares from an expired market.
    /// @param liquidator The address of the liquidator.
    /// @param outcomeIndices The indices of the liquidated outcomes.
    /// @param sharesIn The amounts of shares liquidated per outcome.
    /// @param totalTokensOut The total amount of tokens received.
    event Liquidation(
        address indexed liquidator, uint256[] indexed outcomeIndices, uint256[] sharesIn, uint256 totalTokensOut
    );

    // ===== CONSTANTS =====

    /// @notice Minimum number of outcomes a market can have.
    function MIN_OUTCOME_COUNT() external view returns (uint256);
    /// @notice Maximum number of outcomes a market can have.
    function MAX_OUTCOME_COUNT() external view returns (uint256);
    /// @notice Minimum liquidity depth parameter (k).
    function MIN_B() external view returns (uint256);
    /// @notice Maximum liquidity depth parameter (k).
    function MAX_B() external view returns (uint256);
    /// @notice Minimum trading fee percentage (18 decimal fixed-point).
    function MIN_TRADING_FEE() external view returns (uint256);
    /// @notice Maximum trading fee percentage (18 decimal fixed-point).
    function MAX_TRADING_FEE() external view returns (uint256);
    /// @notice Minimum trading window duration in seconds.
    function MIN_TRADING_WINDOW() external view returns (uint256);
    /// @notice Maximum trading window duration in seconds.
    function MAX_TRADING_WINDOW() external view returns (uint256);
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
    /// @notice The address that receives a portion of the trading fees and the value of market creator's shares (in case he doesn't submit the market's winning outcome within the settlement window).
    function TRADING_FEES_RECIPIENT() external view returns (address);
    /// @notice The percentage of trading fees sent to the TRADING_FEES_RECIPIENT (18 decimal fixed-point).
    function TRADING_FEES_RECIPIENT_PCT() external view returns (uint256);
    /// @notice The decimal scaler for the token (10^(18-decimals)).
    function TOKEN_DECIMAL_SCALER() external view returns (uint256);
    /// @notice The minimum initial liquidity required to create a market (in token decimals).
    function MIN_INITIAL_LIQUIDITY() external view returns (uint256);
    /// @notice The maximum initial liquidity allowed when creating a market (in token decimals).
    function MAX_INITIAL_LIQUIDITY() external view returns (uint256);

    // ===== INITIALIZATION IMMUTABLES =====

    /// @notice The address that created this market.
    function marketCreator() external view returns (address);

    // ===== EXTERNAL MUTATING FUNCTIONS =====

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

    /// @notice Submits the winning outcome and distributes fees and creator rewards. Only callable by the gateway.
    /// @param caller The address submitting the winner (must be the market creator).
    /// @param winningOutcomeIdx The index of the winning outcome.
    function submitWinner(address caller, uint256 winningOutcomeIdx) external;

    /// @notice Redeems a user's winning outcome shares for tokens. Only callable by the gateway.
    /// @param redeemer The address redeeming shares.
    /// @return sharesIn The number of winning shares redeemed.
    /// @return tokensOut The number of tokens received.
    function redeem(address redeemer) external returns (uint256 sharesIn, uint256 tokensOut);

    /// @notice Liquidates the market creator's initial shares from an expired market. Only callable by the gateway.
    /// @return _totalTokensOut The total tokens sent to the trading fees recipient.
    // function liquidateMarketCreationShares() external returns (uint256 _totalTokensOut);

    /// @notice Liquidates a user's shares from an expired market. Only callable by the gateway.
    /// @param liquidator The address liquidating shares.
    /// @param outcomeIndices The indices of outcomes to liquidate.
    /// @return sharesIn The amounts of shares liquidated per outcome.
    /// @return totalTokensOut The total number of tokens received.
    function liquidate(address liquidator, uint256[] calldata outcomeIndices)
        external
        returns (uint256[] memory sharesIn, uint256 totalTokensOut);

    // ===== EXTERNAL VIEWS =====

    // Market Info

    /// @return market The full market struct including configuration and state.
    function getMarket() external view returns (Market memory market);

    /// @return The current lifecycle status of the market.
    function marketStatus() external view returns (MarketStatus);

    // Spot Price

    /// @param outcomeIdx The index of the outcome.
    /// @return The spot price of the given outcome.
    function spotPrice(uint256 outcomeIdx) external view returns (uint256);

    /// @param outcomeIndices The indices of the outcomes.
    /// @return The spot prices for the given outcomes.
    function spotPrices(uint256[] calldata outcomeIndices) external view returns (uint256[] memory);

    // Spot Probability

    /// @param outcomeIdx The index of the outcome.
    /// @return The spot implied probability of the given outcome.
    function spotImpliedProbability(uint256 outcomeIdx) external view returns (uint256);

    /// @param outcomeIndices The indices of the outcomes.
    /// @return The spot implied probabilities for the given outcomes.
    function spotImpliedProbabilities(uint256[] calldata outcomeIndices) external view returns (uint256[] memory);

    // Supplies

    /// @param outcomeIdx The outcome index.
    /// @return The total supply of shares for the given outcome.
    function totalSupply(uint256 outcomeIdx) external view returns (uint256);

    /// @param outcomeIndices The indices of the outcomes.
    /// @return The total supplies for the given outcomes.
    function totalSupplies(uint256[] calldata outcomeIndices) external view returns (uint256[] memory);

    // Balances

    /// @param owner The address of the owner.
    /// @param outcomeIdx The outcome index.
    /// @return The share balance of the given owner for the given outcome.
    function balanceOf(address owner, uint256 outcomeIdx) external view returns (uint256);

    /// @param owners The addresses of the owners.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The share balances for the given owner-outcome pairs.
    function batchBalanceOf(address[] calldata owners, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    /// @return The sum of all outcome supplies (used for liquidation calculations).
    function outcomeSuppliesSum() external view returns (uint256);

    /// @dev Although these shares technically belong to the market creator, they are minted to this smart contract (not to the market creator).
    /// @return The number of shares per outcome granted to the market creator at market creation.
    function marketCreatorSharesPerOutcome() external view returns (uint256);

    /// @return Whether the market creator's initial shares have been liquidated.
    // function marketCreationSharesLiquidated() external view returns (bool);

    /// @return tokensOut The current token value of the market creator's initial shares.
    // function marketCreationSharesValue() external view returns (uint256 tokensOut);
}
