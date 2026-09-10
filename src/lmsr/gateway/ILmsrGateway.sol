// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Interfaces
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDelphiFactory} from "src/factory/IDelphiFactory.sol";
import {ILmsrGatewayErrors} from "./ILmsrGatewayErrors.sol";

/// @title ILmsrGateway
/// @notice Interface for the gateway contract that serves as the entry point for interacting with lmsr markets.
/// @dev All market-facing functions require the market proxy to be deployed by the registered factory.
interface ILmsrGateway is ILmsrGatewayErrors {
    // ========== EVENTS ==========

    /// @notice Emitted when a user buys outcome shares through the gateway.
    /// @param marketProxy The market proxy contract.
    /// @param buyer The address of the buyer.
    /// @param outcomeIdx The index of the purchased outcome.
    /// @param tokensIn The amount of tokens spent.
    /// @param sharesOut The amount of outcome shares received.
    event GatewayBuy(
        ILmsrMarket indexed marketProxy,
        address indexed buyer,
        uint256 indexed outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 outcomeNewExp,
        uint256 newExpSum
    );

    /// @notice Emitted when a user sells outcome shares through the gateway.
    /// @param marketProxy The market proxy contract.
    /// @param seller The address of the seller.
    /// @param outcomeIdx The index of the sold outcome.
    /// @param sharesIn The amount of outcome shares sold.
    /// @param tokensOut The amount of tokens received.
    event GatewaySell(
        ILmsrMarket indexed marketProxy,
        address indexed seller,
        uint256 indexed outcomeIdx,
        uint256 sharesIn,
        uint256 tokensOut,
        uint256 outcomeNewExp,
        uint256 newExpSum
    );

    /// @notice Emitted when the oracle relayer address is updated.
    /// @param previousRelayer The previous oracle relayer address.
    /// @param newRelayer The new oracle relayer address.
    event OracleRelayerSet(address indexed previousRelayer, address indexed newRelayer);

    /// @notice Emitted when resolution is requested for a market.
    /// @param marketProxy The market proxy address.
    /// @param keeper The address that triggered resolution and received the keeper fee.
    event MarketResolutionRequested(address indexed marketProxy, address indexed keeper);

    /// @notice Emitted when a market is settled through the gateway.
    /// @param marketProxy The market proxy contract address.
    /// @param winningOutcomeIdx The index of the winning outcome.
    event GatewayMarketSettled(address indexed marketProxy, uint256 winningOutcomeIdx);

    /// @notice Emitted when a market is transitioned to FAILED status through the gateway.
    /// @param marketProxy The market proxy contract address.
    event GatewayMarketFailed(address indexed marketProxy);

    /// @notice Emitted when a user redeems winning shares for tokens.
    /// @param marketProxy The market proxy contract.
    /// @param redeemer The address of the redeemer.
    /// @param sharesIn The amount of winning shares redeemed.
    /// @param tokensOut The amount of tokens received.
    event GatewayRedemption(
        ILmsrMarket indexed marketProxy, address indexed redeemer, uint256 sharesIn, uint256 tokensOut
    );

    /// @notice Emitted when a user liquidates shares across multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param liquidator The address of the liquidator.
    /// @param outcomeIndices The indices of the liquidated outcomes.
    /// @param sharesIn The amounts of shares liquidated per outcome.
    /// @param totalTokensOut The total amount of tokens received.
    event GatewayLiquidation(
        ILmsrMarket indexed marketProxy,
        address indexed liquidator,
        uint256[] outcomeIndices,
        uint256[] sharesIn,
        uint256 totalTokensOut
    );

    // ========== FUNCTIONS ==========

    /// @notice Buys an exact amount of outcome shares, spending at most `maxTokensIn` tokens, using ERC2612 permit for approval.
    /// @param marketProxy The market proxy contract to buy from.
    /// @param outcomeIdx The index of the outcome to buy.
    /// @param sharesOut The exact number of outcome shares to receive.
    /// @param maxTokensIn The maximum number of tokens the caller is willing to spend, and the amount to approve via permit.
    /// @param deadline The deadline for the permit signature.
    /// @param v The recovery byte of the signature.
    /// @param r Half of the ECDSA signature pair.
    /// @param s Half of the ECDSA signature pair.
    /// @return tokensIn The actual number of tokens spent.
    function buyExactOutWithPermit(
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 tokensIn, uint256 outcomeNewExp, uint256 newExpSum);

    /// @notice Buys an exact amount of outcome shares, spending at most `maxTokensIn` tokens.
    /// @param marketProxy The market proxy contract to buy from.
    /// @param outcomeIdx The index of the outcome to buy.
    /// @param sharesOut The exact number of outcome shares to receive.
    /// @param maxTokensIn The maximum number of tokens the caller is willing to spend.
    /// @return tokensIn The actual number of tokens spent.
    function buyExactOut(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut, uint256 maxTokensIn)
        external
        returns (uint256 tokensIn, uint256 outcomeNewExp, uint256 newExpSum);

    /// @notice Sells an exact amount of outcome shares, receiving at least `minTokensOut` tokens.
    /// @param marketProxy The market proxy contract to sell to.
    /// @param outcomeIdx The index of the outcome to sell.
    /// @param sharesIn The exact number of outcome shares to sell.
    /// @param minTokensOut The minimum number of tokens the caller is willing to receive.
    /// @return tokensOut The actual number of tokens received.
    function sellExactIn(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesIn, uint256 minTokensOut)
        external
        returns (uint256 tokensOut, uint256 outcomeNewExp, uint256 newExpSum);

    /// @notice Initiates the resolution process for a market. Permissionless — any keeper may call this.
    ///         Sets the settlement lock and forwards the request to the oracle relayer.
    /// @dev Reverts with CannotResolveMarketYet (bubbled up from the market) while
    ///      `block.timestamp < market.config.earliestResolveTime`: trading close and resolution
    ///      eligibility are separated by the market's configured resolve delay.
    /// @param marketProxy The market proxy contract address.
    function resolveMarket(address marketProxy) external;

    /// @notice Settles a market with the winning outcome. Only callable by the oracle relayer.
    ///         Settles the market, then atomically transfers the oracle fee to the recipient.
    /// @param marketProxy The market proxy contract address.
    /// @param winningOutcomeIdx The index of the winning outcome.
    /// @param oracleFeeRecipient The address to receive the oracle fee (e.g. Truebit treasury).
    function settleMarket(address marketProxy, uint256 winningOutcomeIdx, address oracleFeeRecipient)
        external
        returns (uint256 losingPayout, uint256 tradingFeesRecipientTradingFeesCut, uint256 marketCreatorTradingFeesCut);

    /// @notice Transitions a market to FAILED status. Only callable by the oracle relayer.
    ///         Returns the oracle fee to the market creator atomically.
    /// @param marketProxy The market proxy contract address.
    function failMarket(address marketProxy) external;

    /// @notice Sets the oracle relayer address. Only callable by the owner.
    /// @param oracleRelayer_ The new oracle relayer address.
    function setOracleRelayer(address oracleRelayer_) external;

    /// @notice Redeems the caller's winning outcome shares for tokens.
    /// @param marketProxy The market proxy contract.
    /// @return sharesIn The number of winning shares redeemed.
    /// @return tokensOut The number of tokens received.
    function redeem(ILmsrMarket marketProxy) external returns (uint256 sharesIn, uint256 tokensOut);

    /// @notice Liquidates the caller's shares across multiple outcomes for tokens.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes to liquidate.
    /// @return sharesIn The amounts of shares liquidated per outcome.
    /// @return totalTokensOut The total number of tokens received.
    function liquidate(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        returns (uint256[] memory sharesIn, uint256 totalTokensOut);

    /// @notice Sweeps claimable rewards on an EXPIRED/FAILED market and retries any pending
    ///         market-creator transfer. Permissionless.
    /// @param marketProxy The market proxy contract.
    function trySweep(ILmsrMarket marketProxy) external;

    // ========== VIEWS ==========

    // Constants

    /// @notice Minimum shares in/out for buy/sell operations (0.01 shares; shares use 18 decimals).
    function MIN_SHARES_DELTA() external view returns (uint256);

    // Immutables

    /// @notice The ERC-20 token all markets trade in.
    function TOKEN() external view returns (IERC20Metadata);
    /// @notice The token decimal scaler: 10^(18 - token decimals).
    function TOKEN_DECIMAL_SCALER() external view returns (uint256);
    /// @notice Minimum token amount for buy/sell operations (0.01 tokens, in token decimals).
    function MIN_TOKENS_DELTA() external view returns (uint256);

    // State Variables

    /// @notice Returns the Delphi factory contract.
    /// @return The factory contract address.
    function delphiFactory() external view returns (IDelphiFactory);

    /// @notice Returns the oracle relayer address.
    function oracleRelayer() external view returns (address);

    /// @notice Returns whether settlement is currently locked for a market proxy.
    /// @param marketProxy The market proxy contract address.
    function settlementLocked(address marketProxy) external view returns (bool);

    // Implementation Configuration

    /// @notice Returns the minimum number of outcomes allowed for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum outcome count.
    function minOutcomeCount(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum number of outcomes allowed for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum outcome count.
    function maxOutcomeCount(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed b parameter for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum b value.
    function minB(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed b parameter for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum b value.
    function maxB(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed trading fee for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum trading fee.
    function minTradingFee(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed trading fee for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum trading fee.
    function maxTradingFee(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed trading window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum trading window in seconds.
    function minTradingWindow(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed trading window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum trading window in seconds.
    function maxTradingWindow(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the minimum allowed settlement window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The minimum settlement window in seconds.
    function minSettlementWindow(ILmsrMarket marketProxy) external view returns (uint256);

    /// @notice Returns the maximum allowed settlement window duration for a market.
    /// @param marketProxy The market proxy contract.
    /// @return The maximum settlement window in seconds.
    function maxSettlementWindow(ILmsrMarket marketProxy) external view returns (uint256);

    // Quoting

    /// @notice Calculates how many tokens must be spent to buy an exact amount of outcome shares.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @param sharesOut The desired number of outcome shares.
    /// @return tokensIn The number of tokens required (including fees).
    function quoteBuyExactOut(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut)
        external
        view
        returns (uint256 tokensIn, uint256 outcomeNewExp, uint256 newExpSum);

    /// @notice Calculates how many tokens will be received for selling an exact amount of outcome shares.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @param sharesIn The number of outcome shares to sell.
    /// @return tokensOut The number of tokens received (after fees).
    function quoteSellExactIn(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesIn)
        external
        view
        returns (uint256 tokensOut, uint256 outcomeNewExp, uint256 newExpSum);

    // Market Info

    /// @notice Returns the address that created the market.
    /// @param marketProxy The market proxy contract.
    /// @return The market creator's address.
    function marketCreator(ILmsrMarket marketProxy) external view returns (address);

    /// @notice Returns the market's metadata URI.
    /// @param marketProxy The market proxy contract.
    /// @return The verifiable URI containing market metadata.
    function marketMetadata(ILmsrMarket marketProxy) external view returns (IDelphiMarket.VerifiableUri memory);

    /// @notice Returns the full market struct including configuration and state.
    /// @param marketProxy The market proxy contract.
    /// @return market The market data.
    function getMarket(ILmsrMarket marketProxy) external view returns (ILmsrMarket.Market memory market);

    /// @notice Returns the current status of the market.
    /// @param marketProxy The market proxy contract.
    /// @return The market status enum value.
    function marketStatus(ILmsrMarket marketProxy) external view returns (ILmsrMarket.MarketStatus);

    // Spot Prices

    /// @notice Returns the spot price of a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @return The spot price.
    function spotPrice(ILmsrMarket marketProxy, uint256 outcomeIdx) external view returns (uint256);

    /// @notice Returns the spot prices for multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The spot prices array.
    function spotPrices(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    // Spot Implied Probabilities

    /// @notice Returns the spot implied probability of a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIdx The index of the outcome.
    /// @return The implied probability.
    function spotImpliedProbability(ILmsrMarket marketProxy, uint256 outcomeIdx) external view returns (uint256);

    /// @notice Returns the spot implied probabilities for multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The implied probabilities array.
    function spotImpliedProbabilities(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    // Supplies

    /// @notice Returns the total supply of shares for a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param id The outcome index.
    /// @return The total supply.
    function totalSupply(ILmsrMarket marketProxy, uint256 id) external view returns (uint256);

    /// @notice Returns the total supplies for multiple outcomes.
    /// @param marketProxy The market proxy contract.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The total supplies array.
    function totalSupplies(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    // Balances

    /// @notice Returns the share balance of an owner for a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param owner The address of the owner.
    /// @param id The outcome index.
    /// @return The balance.
    function balanceOf(ILmsrMarket marketProxy, address owner, uint256 id) external view returns (uint256);

    /// @notice Returns the share balances for multiple owner-outcome pairs.
    /// @param marketProxy The market proxy contract.
    /// @param owners The addresses of the owners.
    /// @param outcomeIndices The indices of the outcomes.
    /// @return The balances array.
    function batchBalanceOf(ILmsrMarket marketProxy, address[] calldata owners, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory);

    /// @notice Returns the token allowance granted by an owner to a spender for a specific outcome.
    /// @param marketProxy The market proxy contract.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @param id The outcome index.
    /// @return The allowance amount.
    function allowance(ILmsrMarket marketProxy, address owner, address spender, uint256 id)
        external
        view
        returns (uint256);

    /// @notice Returns whether an address is an approved operator for another address.
    /// @param marketProxy The market proxy contract.
    /// @param owner The address of the owner.
    /// @param spender The address of the potential operator.
    /// @return True if the spender is an approved operator.
    function isOperator(ILmsrMarket marketProxy, address owner, address spender) external view returns (bool);
}
