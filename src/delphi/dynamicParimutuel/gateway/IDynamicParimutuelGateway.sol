// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Interfaces
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDelphiFactory} from "src/delphi/factory/IDelphiFactory.sol";
import {IDynamicParimutuelGatewayErrors} from "./IDynamicParimutuelGatewayErrors.sol";

/// @title IDynamicParimutuelGateway
/// @notice Interface for the gateway contract that serves as the entry point for interacting with dynamic parimutuel markets.
/// @dev All market-facing functions require the market proxy to be deployed by the registered factory.
interface IDynamicParimutuelGateway is IDynamicParimutuelGatewayErrors {
    // ========== EVENTS ==========

    /// @notice Emitted when a user buys outcome shares through the gateway.
    /// @param marketProxy The market proxy contract.
    /// @param buyer The address of the buyer.
    /// @param outcomeIdx The index of the purchased outcome.
    /// @param tokensIn The amount of tokens spent.
    /// @param sharesOut The amount of outcome shares received.
    event GatewayBuy(
        IDynamicParimutuelMarket indexed marketProxy,
        address indexed buyer,
        uint256 indexed outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut
    );

    /// @notice Emitted when a user sells outcome shares through the gateway.
    /// @param marketProxy The market proxy contract.
    /// @param seller The address of the seller.
    /// @param outcomeIdx The index of the sold outcome.
    /// @param sharesIn The amount of outcome shares sold.
    /// @param tokensOut The amount of tokens received.
    event GatewaySell(
        IDynamicParimutuelMarket indexed marketProxy,
        address indexed seller,
        uint256 indexed outcomeIdx,
        uint256 sharesIn,
        uint256 tokensOut
    );

    /// @notice Emitted when a winning outcome is submitted for a market.
    /// @param marketProxy The market proxy contract.
    /// @param winningOutcomeIdx The index of the winning outcome.
    event GatewayWinnerSubmitted(IDynamicParimutuelMarket indexed marketProxy, uint256 winningOutcomeIdx);

    /// @notice Emitted when a user redeems winning shares for tokens.
    /// @param marketProxy The market proxy contract.
    /// @param redeemer The address of the redeemer.
    /// @param sharesIn The amount of winning shares redeemed.
    /// @param tokensOut The amount of tokens received.
    event GatewayRedemption(
        IDynamicParimutuelMarket indexed marketProxy, address indexed redeemer, uint256 sharesIn, uint256 tokensOut
    );

    /// @notice Emitted when a user liquidates shares across multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param liquidator The address of the liquidator.
    /// @param outcomeIndices The indices of the liquidated outcomes.
    /// @param sharesIn The amounts of shares liquidated per outcome.
    /// @param totalTokensOut The total amount of tokens received.
    event GatewayLiquidation(
        IDynamicParimutuelMarket indexed marketProxy,
        address indexed liquidator,
        uint256[] indexed outcomeIndices,
        uint256[] sharesIn,
        uint256 totalTokensOut
    );

    // ========== FUNCTIONS ==========

    /// @notice Buys an exact amount of outcome shares, spending at most `maxTokensIn` tokens.
    /// @param marketProxy The market proxy contract to buy from.
    /// @param outcomeIdx The index of the outcome to buy.
    /// @param sharesOut The exact number of outcome shares to receive.
    /// @param maxTokensIn The maximum number of tokens the caller is willing to spend.
    /// @return tokensIn The actual number of tokens spent.
    function buyExactOut(
        IDynamicParimutuelMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn
    ) external returns (uint256 tokensIn);

    /// @notice Sells an exact amount of outcome shares, receiving at least `minTokensOut` tokens.
    /// @param marketProxy The market proxy contract to sell to.
    /// @param outcomeIdx The index of the outcome to sell.
    /// @param sharesIn The exact number of outcome shares to sell.
    /// @param minTokensOut The minimum number of tokens the caller is willing to receive.
    /// @return tokensOut The actual number of tokens received.
    function sellExactIn(
        IDynamicParimutuelMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesIn,
        uint256 minTokensOut
    ) external returns (uint256 tokensOut);

    /// @notice Submits the winning outcome for a market.
    /// @param marketProxy The market proxy contract.
    /// @param winningOutcomeIdx The index of the winning outcome.
    function submitWinner(IDynamicParimutuelMarket marketProxy, uint256 winningOutcomeIdx) external;

    /// @notice Redeems the caller's winning outcome shares for tokens.
    /// @param marketProxy The market proxy contract.
    /// @return sharesIn The number of winning shares redeemed.
    /// @return tokensOut The number of tokens received.
    function redeem(IDynamicParimutuelMarket marketProxy) external returns (uint256 sharesIn, uint256 tokensOut);

    /// @notice Liquidates the market creator's initial shares from an expired market and sends proceeds to the trading fees recipient.
    /// @param marketProxy The market proxy contract.
    /// @return _totalTokensOut The total tokens sent to the trading fees recipient.
    function liquidateMarketCreationShares(IDynamicParimutuelMarket marketProxy)
        external
        returns (uint256 _totalTokensOut);

    /// @notice Liquidates the caller's shares across multiple outcomes for tokens.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes to liquidate.
    /// @return sharesIn The amounts of shares liquidated per outcome.
    /// @return totalTokensOut The total number of tokens received.
    function liquidate(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        returns (uint256[] memory sharesIn, uint256 totalTokensOut);

    // ========== VIEWS ==========

    // Constants

    /// @notice Minimum shares in/out for buy/sell operations.
    function MIN_SHARES_DELTA() external view returns (uint256);

    // Immutables
    function TOKEN() external view returns (IERC20Metadata);
    function TOKEN_DECIMAL_SCALER() external view returns (uint256);
    function MIN_TOKENS_DELTA() external view returns (uint256);

    // State Variables

    /// @notice Returns the Delphi factory contract.
    /// @return The factory contract address.
    function delphiFactory() external view returns (IDelphiFactory);

    // Implementation Configuration

    /// @notice Returns the minimum number of outcomes allowed for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum outcome count.
    function minOutcomeCount(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum number of outcomes allowed for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum outcome count.
    function maxOutcomeCount(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed k parameter for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum k value.
    function minK(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed k parameter for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum k value.
    function maxK(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed trading fee for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum trading fee.
    function minTradingFee(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed trading fee for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum trading fee.
    function maxTradingFee(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed trading window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum trading window in seconds.
    function minTradingWindow(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed trading window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum trading window in seconds.
    function maxTradingWindow(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed settlement window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum settlement window in seconds.
    function minSettlementWindow(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed settlement window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum settlement window in seconds.
    function maxSettlementWindow(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum initial deposit required to create a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum initial deposit.
    function minInitialDeposit(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum initial deposit allowed when creating a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum initial deposit.
    function maxInitialDeposit(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    // Quoting

    /// @notice Calculates how many tokens must be spent to buy an exact amount of outcome shares.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @param sharesOut The desired number of outcome shares.
    /// @return tokensIn The number of tokens required (including fees).
    function quoteBuyExactOut(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut)
        external
        view
        returns (uint256 tokensIn);

    /// @notice Calculates how many tokens will be received for selling an exact amount of outcome shares.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @param sharesIn The number of outcome shares to sell.
    /// @return tokensOut The number of tokens received (after fees).
    function quoteSellExactIn(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx, uint256 sharesIn)
        external
        view
        returns (uint256 tokensOut);

    // Market Info

    /// @notice Returns the address that created the market.
    /// @param marketProxy The market proxy contract.
    /// @return The market creator's address.
    function marketCreator(IDynamicParimutuelMarket marketProxy) external view returns (address);

    /// @notice Returns the market's metadata URI.
    /// @param marketProxy The market proxy contract.
    /// @return The verifiable URI containing market metadata.
    function marketMetadata(IDynamicParimutuelMarket marketProxy)
        external
        view
        returns (IDelphiMarket.VerifiableUri memory);

    /// @notice Returns the full market struct including configuration and state.
    /// @param marketProxy The market proxy contract.
    /// @return market The market data.
    function getMarket(IDynamicParimutuelMarket marketProxy)
        external
        view
        returns (IDynamicParimutuelMarket.Market memory market);

    /// @notice Returns the current status of the market.
    /// @param marketProxy The market proxy contract.
    /// @return The market status enum value.
    function marketStatus(IDynamicParimutuelMarket marketProxy)
        external
        view
        returns (IDynamicParimutuelMarket.MarketStatus);

    // Spot Prices

    /// @notice Returns the spot price of a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @return The spot price.
    function spotPrice(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx) external view returns (uint256);

    /// @notice Returns the spot prices for multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The spot prices array.
    function spotPrices(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    // Spot Implied Probabilities

    /// @notice Returns the spot implied probability of a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @return The implied probability.
    function spotImpliedProbability(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx)
        external
        view
        returns (uint256);

    /// @notice Returns the spot implied probabilities for multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The implied probabilities array.
    function spotImpliedProbabilities(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    // Supplies

    /// @notice Returns the total supply of shares for a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param id The outcome index.
    /// @return The total supply.
    function totalSupply(IDynamicParimutuelMarket marketProxy, uint256 id) external view returns (uint256);

    /// @notice Returns the total supplies for multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The total supplies array.
    function totalSupplies(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    // Balances

    /// @notice Returns the share balance of an owner for a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param owner The address of the owner.
    /// @param id The outcome index.
    /// @return The balance.
    function balanceOf(IDynamicParimutuelMarket marketProxy, address owner, uint256 id) external view returns (uint256);

    /// @notice Returns the share balances for multiple owner-outcome pairs.
    /// @param marketProxy The market proxy contract.
    /// @param owners The addresses of the owners.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The balances array.
    function batchBalanceOf(
        IDynamicParimutuelMarket marketProxy,
        address[] calldata owners,
        uint256[] calldata outcomeIndices
    ) external view returns (uint256[] memory);

    /// @notice Returns the token allowance granted by an owner to a spender for a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @param id The outcome index.
    /// @return The allowance amount.
    function allowance(IDynamicParimutuelMarket marketProxy, address owner, address spender, uint256 id)
        external
        view
        returns (uint256);

    /// @notice Returns whether an address is an approved operator for another address.
    /// @param marketProxy The market proxy contract.
    /// @param owner The address of the owner.
    /// @param spender The address of the potential operator.
    /// @return True if the spender is an approved operator.
    function isOperator(IDynamicParimutuelMarket marketProxy, address owner, address spender)
        external
        view
        returns (bool);

    /// @notice Returns the sum of all outcome supplies for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The sum of all outcome supplies.
    function outcomeSuppliesSum(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns the number of shares per outcome minted to the market at creation.
    /// @param marketProxy The market proxy contract.
    /// @return The shares per outcome held by the contract.
    function marketCreatorSharesPerOutcome(IDynamicParimutuelMarket marketProxy) external view returns (uint256);

    /// @notice Returns whether the market creator's initial shares have been liquidated.
    /// @param marketProxy The market proxy contract.
    function marketCreationSharesLiquidated(IDynamicParimutuelMarket marketProxy) external view returns (bool);

    /// @notice Returns the current token value of the market creator's initial shares.
    /// @param marketProxy The market proxy contract.
    /// @return The token value of the creator's shares across all outcomes.
    function marketCreationSharesValue(IDynamicParimutuelMarket marketProxy) external view returns (uint256);
}
