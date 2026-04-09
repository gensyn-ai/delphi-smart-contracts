// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IDynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGateway.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// Interfaces
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";
import {
    IDynamicParimutuelMarketErrors
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketErrors.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDelphiFactory} from "src/delphi/factory/IDelphiFactory.sol";

// Libraries
import {DynamicParimutuelMath} from "src/delphi/dynamicParimutuel/math/DynamicParimutuelMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LmsrMath} from "src/delphi/dynamicParimutuel/math/LmsrMath.sol";

import {console} from "forge-std/console.sol";

/// @title DynamicParimutuelGateway
/// @notice Entry point for interacting with dynamic parimutuel markets.
/// @dev After validating it was deployed by the registered factory, the gateway calls the market proxy (which in turn calls the market implementation).
///      All rounding in quote functions is done against the user to prevent value extraction.
contract DynamicParimutuelGateway is IDynamicParimutuelGateway, Initializable {
    // ========== INTERNAL CONSTANTS ==========
    uint256 internal constant _MIN_TOKENS_DELTA_18 = 0.01e18;

    // ========== PUBLIC CONSTANTS ==========

    /// @inheritdoc IDynamicParimutuelGateway
    uint256 public constant override MIN_SHARES_DELTA = 1e6;

    // ========== INTERNAL IMMUTABLES ==========
    address internal immutable DEPLOYER;

    // ========== PUBLIC IMMUTABLES ==========
    IERC20Metadata public immutable override TOKEN;
    uint256 public immutable override TOKEN_DECIMAL_SCALER;
    uint256 public immutable override MIN_TOKENS_DELTA;

    // ========== STATE VARIABLES ==========

    /// @inheritdoc IDynamicParimutuelGateway
    IDelphiFactory public override delphiFactory;

    // ========== LIBRARIES ==========
    using DynamicParimutuelMath for uint256;
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;
    using LmsrMath for uint256;

    // ========== CONSTRUCTOR ==========
    constructor(IERC20Metadata token_) {
        // Get token decimals
        uint8 tokenDecimals = token_.decimals();

        // Checks: Validate token decimals
        if (tokenDecimals < 6) {
            revert IDynamicParimutuelMarketErrors.TokenDecimalsTooLow(tokenDecimals);
        }
        if (tokenDecimals > 18) {
            revert IDynamicParimutuelMarketErrors.TokenDecimalsTooHigh(tokenDecimals);
        }

        // Effects: Set immutables
        DEPLOYER = msg.sender;
        TOKEN = token_;
        TOKEN_DECIMAL_SCALER = 10 ** (18 - tokenDecimals);
        MIN_TOKENS_DELTA = _MIN_TOKENS_DELTA_18 / TOKEN_DECIMAL_SCALER;
    }

    // ========== MODIFIERS ==========

    /// @dev Reverts if the market proxy was not deployed by the registered factory.
    modifier ifDeployedByFactory(IDynamicParimutuelMarket marketProxy) {
        _ifDeployedByFactory(marketProxy);
        _;
    }

    /// @dev Reverts if the market is not in the OPEN status.
    modifier ifOpen(IDynamicParimutuelMarket marketProxy) {
        _ifOpen(marketProxy);
        _;
    }

    // ========== INITIALIZER ==========

    /// @notice Initializes the gateway with a Delphi factory. Can only be called once, by the deployer.
    /// @param delphiFactory_ The Delphi factory contract.
    function initialize(IDelphiFactory delphiFactory_) external initializer {
        // Checks: Validate delphi factory
        if (msg.sender != DEPLOYER) {
            revert InitializerNotDeployer(msg.sender, DEPLOYER);
        }
        if (address(delphiFactory_) == address(0)) {
            revert DelphiFactoryIsZeroAddress();
        }
        if (address(delphiFactory_).code.length == 0) {
            revert DelphiFactoryIsNotContract(address(delphiFactory_));
        }

        // Effects: Set delphi factory
        delphiFactory = delphiFactory_;
    }

    // ========== FUNCTIONS ==========

    /// @inheritdoc IDynamicParimutuelGateway
    function buyExactOut(
        IDynamicParimutuelMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn
    ) external ifDeployedByFactory(marketProxy) returns (uint256 tokensIn) {
        // Calculate tokens in
        tokensIn = quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);

        // Checks: Validate tokens in
        if (tokensIn > maxTokensIn) {
            revert TokensInExceedsMax(tokensIn, maxTokensIn);
        }

        // Effects: Emit event
        emit GatewayBuy(marketProxy, msg.sender, outcomeIdx, tokensIn, sharesOut);

        // Checks/Effects/Interactions: Buy
        IDynamicParimutuelMarket(marketProxy).buy(msg.sender, outcomeIdx, tokensIn, sharesOut);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function sellExactIn(
        IDynamicParimutuelMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesIn,
        uint256 minTokensOut
    ) external ifDeployedByFactory(marketProxy) returns (uint256 tokensOut) {
        // Calculate tokens out
        tokensOut = quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);

        // Checks: Validate tokens out
        if (tokensOut < minTokensOut) {
            revert TokensOutBelowMin(tokensOut, minTokensOut);
        }

        // Effects: Emit event
        emit GatewaySell(marketProxy, msg.sender, outcomeIdx, sharesIn, tokensOut);

        // Checks/Effects/Interactions: Sell
        IDynamicParimutuelMarket(marketProxy).sell(msg.sender, outcomeIdx, sharesIn, tokensOut);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function submitWinner(IDynamicParimutuelMarket marketProxy, uint256 winningOutcomeIdx)
        external
        ifDeployedByFactory(marketProxy)
    {
        // Effects: Emit event
        emit GatewayWinnerSubmitted(marketProxy, winningOutcomeIdx);

        // Checks/Effects/Interactions: Submit winner
        IDynamicParimutuelMarket(marketProxy).submitWinner(msg.sender, winningOutcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function redeem(IDynamicParimutuelMarket marketProxy)
        external
        ifDeployedByFactory(marketProxy)
        returns (uint256 sharesIn, uint256 tokensOut)
    {
        // Checks/Effects/Interactions: Redeem
        (sharesIn, tokensOut) = IDynamicParimutuelMarket(marketProxy).redeem(msg.sender);

        // Effects: Emit event
        emit GatewayRedemption(marketProxy, msg.sender, sharesIn, tokensOut);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function liquidate(IDynamicParimutuelMarket marketProxy, uint256[] memory outcomeIndices)
        external
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory sharesIn, uint256 totalTokensOut)
    {
        // Checks/Effects/Interactions: Liquidate
        (sharesIn, totalTokensOut) = IDynamicParimutuelMarket(marketProxy).liquidate(msg.sender, outcomeIndices);

        // Effects: Emit event
        emit GatewayLiquidation(marketProxy, msg.sender, outcomeIndices, sharesIn, totalTokensOut);
    }

    // ========== VIEWS ==========

    // Implementation Configuration

    /// @inheritdoc IDynamicParimutuelGateway
    function minOutcomeCount(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_OUTCOME_COUNT();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function maxOutcomeCount(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_OUTCOME_COUNT();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function minK(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_B();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function maxK(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_B();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function minTradingFee(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_TRADING_FEE();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function maxTradingFee(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_TRADING_FEE();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function minTradingWindow(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_TRADING_WINDOW();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function maxTradingWindow(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_TRADING_WINDOW();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function minSettlementWindow(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_SETTLEMENT_WINDOW();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function maxSettlementWindow(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_SETTLEMENT_WINDOW();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function minInitialLiquidity(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_INITIAL_LIQUIDITY();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function maxInitialLiquidity(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_INITIAL_LIQUIDITY();
    }

    // Quoting

    /// @inheritdoc IDynamicParimutuelGateway
    function quoteBuyExactOut(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut)
        public
        view
        ifDeployedByFactory(marketProxy)
        ifOpen(marketProxy)
        returns (uint256 tokensIn)
    {
        // Checks: Ensure shares out is at least min shares delta
        if (sharesOut < MIN_SHARES_DELTA) {
            revert SharesOutBelowMinDelta(sharesOut, MIN_SHARES_DELTA);
        }

        // Get outcome supply
        uint256 outcomeCurrentSupply = marketProxy.totalSupply(outcomeIdx);

        // Get market
        IDynamicParimutuelMarket.Market memory market = marketProxy.getMarket();

        // Calculate & Validate outcome new exp input
        uint256 outcomeNewExpInput = ((outcomeCurrentSupply + sharesOut) * 1e18 / market.b);
        if (outcomeNewExpInput > LmsrMath.MAX_EXP_INPUT) {
            revert OutcomeNewExpInputTooLarge(outcomeNewExpInput, LmsrMath.MAX_EXP_INPUT);
        }

        // Calculate exps
        // Note: No rounding, to not propagate error to future trades
        uint256 outcomeNewExp = outcomeNewExpInput._computeExp();
        uint256 outcomeCurrentExp = (outcomeCurrentSupply * 1e18 / market.b)._computeExp();

        // Checks: Calculate & Validate new sum term
        // Note: calculate most accurate approximation (nor upper nor lower bound)
        uint256 newExpSum = market.expSum + outcomeNewExp - outcomeCurrentExp;
        assert(newExpSum > market.expSum);

        // Checks: Calculate & Validate sum term square roots
        // Note: Every operation is rounded against the user
        uint256 newExpSumUpperBound = newExpSum._getExpUpperBound();
        uint256 currentExpSumLowerBound = market.expSum._getExpLowerBound();
        assert(newExpSumUpperBound > currentExpSumLowerBound);

        // Checks: Calculate & Validate ratio
        // Note: Ceil the div to round against the user
        uint256 ratio = newExpSumUpperBound.mulDivUp(1e18, currentExpSumLowerBound);
        assert(ratio > 1e18);

        // Calculate the upper bound of ln of ratio (to round against the user)
        uint256 ratioLnUpperBound = ratio._computeLnUpperBound();

        // Calculate fee adjusted b
        uint256 feeAdjustedB = market.b * (1e18 + market.config.tradingFee);

        // Checks: Calculate tokens in (with fee)
        // Note: To round against the user, we ceil the division
        tokensIn = feeAdjustedB.mulDiv(ratioLnUpperBound, 1e36 * TOKEN_DECIMAL_SCALER, Math.Rounding.Ceil);
        tokensIn += 1;

        // // Checks: Validate net tokens in
        // if (netTokensIn == 0) {
        //     revert ZeroNetTokensIn();
        // }

        // // Add trading fee to net tokens in
        // (tokensIn,) = netTokensIn.addFee(market.config.tradingFee);

        // Checks: Validate tokens in
        if (tokensIn < MIN_TOKENS_DELTA) {
            revert TokensInBelowMin(tokensIn, MIN_TOKENS_DELTA);
        }
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function quoteSellExactIn(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx, uint256 sharesIn)
        public
        view
        ifDeployedByFactory(marketProxy)
        ifOpen(marketProxy)
        returns (uint256 tokensOut)
    {
        // Checks: Ensure shares in is at least min shares delta
        if (sharesIn < MIN_SHARES_DELTA) {
            revert SharesInBelowMinDelta(sharesIn, MIN_SHARES_DELTA);
        }

        // Get outcome supply
        uint256 outcomeCurrentSupply = marketProxy.totalSupply(outcomeIdx);

        /// Checks: Ensure shares in does not exceed outcome supply
        if (sharesIn > outcomeCurrentSupply) {
            revert SharesInExceedSupply(sharesIn, outcomeCurrentSupply);
        }

        // Calculate new supply
        uint256 outcomeNewSupply = outcomeCurrentSupply - sharesIn;

        // Checks: Ensure outcome new supply is either zero or at least min shares delta
        if (0 < outcomeNewSupply && outcomeNewSupply < MIN_SHARES_DELTA) {
            revert OutcomeSupplyBelowMinDelta(outcomeNewSupply, MIN_SHARES_DELTA);
        }

        // Get market
        IDynamicParimutuelMarket.Market memory market = marketProxy.getMarket();

        uint256 outcomeNewExp = (outcomeNewSupply * 1e18 / market.b)._computeExp();
        uint256 outcomeCurrentExp = (outcomeCurrentSupply * 1e18 / market.b)._computeExp();

        // Calculate new sum term
        // Note: calculate most accurate approximation (nor upper nor lower bound)
        uint256 newExpSum = market.expSum + outcomeNewExp - outcomeCurrentExp;
        require(newExpSum < market.expSum, "newExpSum not < market.expSum");

        // Calculate sum term square roots
        // Note: Every operation is rounded against the user
        uint256 currentExpSumLowerBound = market.expSum._getExpLowerBound();
        uint256 newExpSumUpperBound = newExpSum._getExpUpperBound();
        if (newExpSumUpperBound >= currentExpSumLowerBound) {
            revert SellOverlap();
        }

        // Calculate ratio
        // Note: instead of negating the log input (which causes numerical instability) and the output, flip the ratio
        // Note: Floor the div to round against the user
        uint256 ratio = currentExpSumLowerBound.mulDivDown(1e18, newExpSumUpperBound);
        console.log("ratio:", ratio);
        require(ratio < 1e18, "ratio not < 1e18");

        // Calculate lower bound of ln of ratio (to round against the user)
        uint256 ratioLnLowerBound = ratio._computeLnLowerBound();

        // Calculate fee adjusted b
        uint256 feeAdjustedB = market.b * (1e18 - market.config.tradingFee);

        // Calculate tokens out (with fee)
        // Note: To round against the user, we floor the division
        tokensOut = feeAdjustedB.mulDiv(ratioLnLowerBound, 1e36 * TOKEN_DECIMAL_SCALER, Math.Rounding.Floor);

        // // Checks: Validate gross tokens out
        // if (grossTokensOut == 0) {
        //     revert GrossTokensOutNotPositive();
        // }

        // // Deduct trading fee from gross tokens out
        // (tokensOut,) = grossTokensOut.deductFee(market.config.tradingFee);

        // Checks: Validate tokens out
        if (tokensOut < MIN_TOKENS_DELTA) {
            revert TokensOutBelowMin(tokensOut, MIN_TOKENS_DELTA);
        }
    }

    // Market Info

    /// @inheritdoc IDynamicParimutuelGateway
    function marketCreator(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (address)
    {
        return marketProxy.marketCreator();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function marketMetadata(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (IDelphiMarket.VerifiableUri memory)
    {
        return marketProxy.getMarketMetadata();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function getMarket(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (IDynamicParimutuelMarket.Market memory)
    {
        return marketProxy.getMarket();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function marketStatus(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (IDynamicParimutuelMarket.MarketStatus)
    {
        return marketProxy.marketStatus();
    }

    // Spot Prices

    /// @inheritdoc IDynamicParimutuelGateway
    function spotPrice(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.spotPrice(outcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function spotPrices(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.spotPrices(outcomeIndices);
    }

    // Spot Implied Probabilities

    /// @inheritdoc IDynamicParimutuelGateway
    function spotImpliedProbability(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.spotImpliedProbability(outcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function spotImpliedProbabilities(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.spotImpliedProbabilities(outcomeIndices);
    }

    // Supplies

    /// @inheritdoc IDynamicParimutuelGateway
    function totalSupply(IDynamicParimutuelMarket marketProxy, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.totalSupply(outcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function totalSupplies(IDynamicParimutuelMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.totalSupplies(outcomeIndices);
    }

    // Balances

    /// @inheritdoc IDynamicParimutuelGateway
    function balanceOf(IDynamicParimutuelMarket marketProxy, address owner, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.balanceOf(owner, outcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function batchBalanceOf(
        IDynamicParimutuelMarket marketProxy,
        address[] calldata owners,
        uint256[] calldata outcomeIndices
    ) external view ifDeployedByFactory(marketProxy) returns (uint256[] memory) {
        return marketProxy.batchBalanceOf(owners, outcomeIndices);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function allowance(IDynamicParimutuelMarket marketProxy, address owner, address spender, uint256 id)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.allowance(owner, spender, id);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function isOperator(IDynamicParimutuelMarket marketProxy, address operator, address spender)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (bool)
    {
        return marketProxy.isOperator(operator, spender);
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function outcomeSuppliesSum(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.outcomeSuppliesSum();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    function marketCreatorSharesPerOutcome(IDynamicParimutuelMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.marketCreatorSharesPerOutcome();
    }

    /// @inheritdoc IDynamicParimutuelGateway
    // function marketCreationSharesLiquidated(IDynamicParimutuelMarket marketProxy)
    //     external
    //     view
    //     ifDeployedByFactory(marketProxy)
    //     returns (bool)
    // {
    //     return marketProxy.marketCreationSharesLiquidated();
    // }

    /// @inheritdoc IDynamicParimutuelGateway
    // function marketCreationSharesValue(IDynamicParimutuelMarket marketProxy)
    //     external
    //     view
    //     ifDeployedByFactory(marketProxy)
    //     returns (uint256 tokensOut)
    // {
    //     return marketProxy.marketCreationSharesValue();
    // }

    // ========== INTERNAL FUNCTIONS ==========

    /// @dev Validates that the gateway is initialized and the market proxy was deployed by the factory.
    /// @param marketProxy The market proxy to validate.
    function _ifDeployedByFactory(IDynamicParimutuelMarket marketProxy) internal view {
        if (_getInitializedVersion() == 0) {
            revert GatewayNotInitialized();
        }

        if (!delphiFactory.marketProxyExists(address(marketProxy))) {
            revert MarketProxyNotDeployedByFactory(address(marketProxy));
        }
    }

    function _ifOpen(IDynamicParimutuelMarket marketProxy) internal view {
        if (marketProxy.marketStatus() != IDynamicParimutuelMarketTypes.MarketStatus.OPEN) {
            revert MarketNotOpen();
        }
    }
}
