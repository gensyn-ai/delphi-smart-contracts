// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

// Interfaces
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {IOracle} from "src/IOracle.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDelphiFactory} from "src/factory/IDelphiFactory.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title LmsrGateway
/// @notice Entry point for interacting with lmsr markets.
/// @dev After validating it was deployed by the registered factory, the gateway calls the market proxy (which in turn calls the market implementation).
///      All rounding in quote functions is done against the user to prevent value extraction.
contract LmsrGateway is ILmsrGateway, Initializable, Ownable2Step {
    // ========== INTERNAL CONSTANTS ==========

    /// @dev Minimum token amount per trade, expressed in 18 decimals (scaled down to token decimals
    ///      in the constructor to produce MIN_TOKENS_DELTA).
    uint256 internal constant _MIN_TOKENS_DELTA_18 = 0.01e18;

    // ========== PUBLIC CONSTANTS ==========

    /// @inheritdoc ILmsrGateway
    uint256 public constant override MIN_SHARES_DELTA = 0.01e18;

    // ========== INTERNAL IMMUTABLES ==========

    /// @dev The gateway deployer; the only address allowed to call initialize().
    address internal immutable DEPLOYER;

    // ========== PUBLIC IMMUTABLES ==========

    /// @inheritdoc ILmsrGateway
    IERC20Metadata public immutable override TOKEN;
    /// @inheritdoc ILmsrGateway
    uint256 public immutable override TOKEN_DECIMAL_SCALER;
    /// @inheritdoc ILmsrGateway
    uint256 public immutable override MIN_TOKENS_DELTA;

    // ========== STATE VARIABLES ==========

    /// @inheritdoc ILmsrGateway
    IDelphiFactory public override delphiFactory;

    /// @inheritdoc ILmsrGateway
    address public override oracleRelayer;

    /// @inheritdoc ILmsrGateway
    mapping(address marketProxy => bool) public override settlementLocked;

    // ========== LIBRARIES ==========
    using LmsrMath for uint256;
    using Math for uint256;

    // ========== CONSTRUCTOR ==========

    /// @notice Deploys the gateway for a given trading token.
    /// @param token_ The ERC-20 token all markets trade in (must be a contract with 6–18 decimals).
    /// @param owner_ The gateway owner (can wire the oracle relayer via setOracleRelayer).
    constructor(IERC20Metadata token_, address owner_) Ownable(owner_) {
        // Checks: Validate token
        if (address(token_) == address(0)) {
            revert TokenIsZeroAddress();
        }
        if (address(token_).code.length == 0) {
            revert TokenIsNotAContract(address(token_));
        }

        // Get token decimals
        uint8 tokenDecimals = token_.decimals();

        // Checks: Validate token decimals
        if (tokenDecimals < 6) {
            revert TokenDecimalsAreTooLow(tokenDecimals);
        }
        if (tokenDecimals > 18) {
            revert TokenDecimalsAreTooHigh(tokenDecimals);
        }

        // Effects: Set immutables
        DEPLOYER = msg.sender;
        TOKEN = token_;
        TOKEN_DECIMAL_SCALER = 10 ** (18 - tokenDecimals);
        MIN_TOKENS_DELTA = _MIN_TOKENS_DELTA_18 / TOKEN_DECIMAL_SCALER;
    }

    // ========== MODIFIERS ==========

    /// @dev Reverts if the market proxy was not deployed by the registered factory.
    modifier ifDeployedByFactory(ILmsrMarket marketProxy) {
        _ifDeployedByFactory(marketProxy);
        _;
    }

    /// @dev Reverts if the market is not in the OPEN status.
    modifier ifOpen(ILmsrMarket marketProxy) {
        _ifOpen(marketProxy);
        _;
    }

    /// @dev Reverts if the caller is not the oracle relayer.
    modifier onlyOracleRelayer() {
        _onlyOracleRelayer();
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

    /// @inheritdoc ILmsrGateway
    function buyExactOutWithPermit(
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external ifDeployedByFactory(marketProxy) returns (uint256 tokensIn, uint256 outcomeNewExp, uint256 newExpSum) {
        try IERC20Permit(address(TOKEN))
            .permit({
                owner: msg.sender,
                spender: address(marketProxy),
                value: maxTokensIn,
                deadline: deadline,
                v: v,
                r: r,
                s: s
            }) {}
        catch {
            uint256 _allowance = TOKEN.allowance(msg.sender, address(marketProxy));
            if (_allowance < maxTokensIn) {
                revert AllowanceTooLow(_allowance, maxTokensIn);
            }
        }

        (tokensIn, outcomeNewExp, newExpSum) = buyExactOut(marketProxy, outcomeIdx, sharesOut, maxTokensIn);
    }

    /// @inheritdoc ILmsrGateway
    function buyExactOut(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut, uint256 maxTokensIn)
        public
        ifDeployedByFactory(marketProxy)
        returns (uint256 tokensIn, uint256 outcomeNewExp, uint256 newExpSum)
    {
        // Calculate tokens in
        (tokensIn, outcomeNewExp, newExpSum) = quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut);

        // Checks: Validate tokens in
        if (tokensIn > maxTokensIn) {
            revert TokensInExceedMaxTokensIn(tokensIn, maxTokensIn);
        }

        // Effects: Emit event
        emit GatewayBuy(marketProxy, msg.sender, outcomeIdx, tokensIn, sharesOut, outcomeNewExp, newExpSum);

        // Checks/Effects/Interactions: Buy
        ILmsrMarket(marketProxy).buy(msg.sender, outcomeIdx, tokensIn, sharesOut);
    }

    /// @inheritdoc ILmsrGateway
    function sellExactIn(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesIn, uint256 minTokensOut)
        external
        ifDeployedByFactory(marketProxy)
        returns (uint256 tokensOut, uint256 outcomeNewExp, uint256 newExpSum)
    {
        // Calculate tokens out
        (tokensOut, outcomeNewExp, newExpSum) = quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);

        // Checks: Validate tokens out
        if (tokensOut < minTokensOut) {
            revert TokensOutBelowMinTokensOut(tokensOut, minTokensOut);
        }

        // Effects: Emit event
        emit GatewaySell(marketProxy, msg.sender, outcomeIdx, sharesIn, tokensOut, outcomeNewExp, newExpSum);

        // Checks/Effects/Interactions: Sell
        ILmsrMarket(marketProxy).sell(msg.sender, outcomeIdx, sharesIn, tokensOut);
    }

    /// @inheritdoc ILmsrGateway
    function setOracleRelayer(address oracleRelayer_) external onlyOwner {
        if (oracleRelayer_ == address(0)) revert OracleRelayerIsZeroAddress();
        if (oracleRelayer_.code.length == 0) revert OracleRelayerIsNotAContract(oracleRelayer_);

        address previous = oracleRelayer;
        oracleRelayer = oracleRelayer_;

        emit OracleRelayerSet(previous, oracleRelayer_);
    }

    /// @inheritdoc ILmsrGateway
    function resolveMarket(address marketProxy) external ifDeployedByFactory(ILmsrMarket(marketProxy)) {
        // Defense-in-depth: unreachable for factory markets; invariant failsafe against future cross-contract changes.
        if (oracleRelayer == address(0)) revert OracleRelayerNotSet();
        if (settlementLocked[marketProxy]) revert SettlementAlreadyLocked(marketProxy);

        // Effects: Lock settlement before calling out
        settlementLocked[marketProxy] = true;

        // Interactions: Transfer keeper fee first — the market's ifStatus(AWAITING_SETTLEMENT) guard is the
        // authoritative check that the market is ready for resolution. Calling this before the oracle
        // request ensures the transaction reverts early (before any oracle-side effects) if the market
        // is not in the correct state.
        ILmsrMarket(marketProxy).transferKeeperFee(msg.sender);

        // Interactions: Request resolution from oracle
        IOracle(oracleRelayer).resolveMarket(marketProxy);

        // Effects: Emit event
        emit MarketResolutionRequested(marketProxy, msg.sender);
    }

    /// @inheritdoc ILmsrGateway
    function settleMarket(address marketProxy, uint256 winningOutcomeIdx, address oracleFeeRecipient)
        external
        onlyOracleRelayer
        ifDeployedByFactory(ILmsrMarket(marketProxy))
        returns (uint256 losingPayout, uint256 tradingFeesRecipientTradingFeesCut, uint256 marketCreatorTradingFeesCut)
    {
        // Checks: a market can only be settled after a gateway-issued resolution request locked it.
        if (!settlementLocked[marketProxy]) revert SettlementNotLocked();

        // Interactions: Settle the market then transfer oracle fee atomically
        (losingPayout, tradingFeesRecipientTradingFeesCut, marketCreatorTradingFeesCut) =
            ILmsrMarket(marketProxy).settleMarket(winningOutcomeIdx, oracleFeeRecipient);

        emit GatewayMarketSettled(marketProxy, winningOutcomeIdx);
    }

    /// @inheritdoc ILmsrGateway
    function failMarket(address marketProxy) external onlyOracleRelayer ifDeployedByFactory(ILmsrMarket(marketProxy)) {
        // Checks: a market can only be failed after a gateway-issued resolution request locked it.
        if (!settlementLocked[marketProxy]) revert SettlementNotLocked();

        // Interactions: Fail the market. Oracle fee is returned to the creator inside
        ILmsrMarket(marketProxy).failMarket();

        emit GatewayMarketFailed(marketProxy);
    }

    /// @inheritdoc ILmsrGateway
    function redeem(ILmsrMarket marketProxy)
        external
        ifDeployedByFactory(marketProxy)
        returns (uint256 sharesIn, uint256 tokensOut)
    {
        // Checks/Effects/Interactions: Redeem
        (sharesIn, tokensOut) = ILmsrMarket(marketProxy).redeem(msg.sender);

        // Effects: Emit event
        emit GatewayRedemption(marketProxy, msg.sender, sharesIn, tokensOut);
    }

    /// @inheritdoc ILmsrGateway
    function liquidate(ILmsrMarket marketProxy, uint256[] memory outcomeIndices)
        external
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory sharesIn, uint256 totalTokensOut)
    {
        // Checks/Effects/Interactions: Liquidate
        (sharesIn, totalTokensOut) = ILmsrMarket(marketProxy).liquidate(msg.sender, outcomeIndices);

        // Effects: Emit event
        emit GatewayLiquidation(marketProxy, msg.sender, outcomeIndices, sharesIn, totalTokensOut);
    }

    /// @inheritdoc ILmsrGateway
    function trySweep(ILmsrMarket marketProxy) external ifDeployedByFactory(marketProxy) {
        ILmsrMarket(marketProxy).trySweep();
    }

    // ========== VIEWS ==========

    // Implementation Configuration

    /// @inheritdoc ILmsrGateway
    function minOutcomeCount(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (uint256) {
        return marketProxy.MIN_OUTCOME_COUNT();
    }

    /// @inheritdoc ILmsrGateway
    function maxOutcomeCount(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (uint256) {
        return marketProxy.MAX_OUTCOME_COUNT();
    }

    /// @inheritdoc ILmsrGateway
    function minB(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (uint256) {
        return marketProxy.MIN_B();
    }

    /// @inheritdoc ILmsrGateway
    function maxB(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (uint256) {
        return marketProxy.MAX_B();
    }

    /// @inheritdoc ILmsrGateway
    function minTradingFee(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (uint256) {
        return marketProxy.MIN_TRADING_FEE();
    }

    /// @inheritdoc ILmsrGateway
    function maxTradingFee(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (uint256) {
        return marketProxy.MAX_TRADING_FEE();
    }

    /// @inheritdoc ILmsrGateway
    function minTradingWindow(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_TRADING_WINDOW();
    }

    /// @inheritdoc ILmsrGateway
    function maxTradingWindow(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_TRADING_WINDOW();
    }

    /// @inheritdoc ILmsrGateway
    function minSettlementWindow(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MIN_SETTLEMENT_WINDOW();
    }

    /// @inheritdoc ILmsrGateway
    function maxSettlementWindow(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.MAX_SETTLEMENT_WINDOW();
    }

    // Quoting

    /// @inheritdoc ILmsrGateway
    function quoteBuyExactOut(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut)
        public
        view
        ifDeployedByFactory(marketProxy)
        ifOpen(marketProxy)
        returns (uint256 tokensIn, uint256 outcomeNewExp, uint256 newExpSum)
    {
        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Checks: Ensure outcome idx is valid
        if (outcomeIdx >= market.config.outcomeCount) {
            revert ILmsrMarketErrors.OutcomeIsOutOfBounds(outcomeIdx, market.config.outcomeCount);
        }

        // Checks: Ensure shares out is at least min shares delta
        if (sharesOut < MIN_SHARES_DELTA) {
            revert SharesOutBelowMinDelta(sharesOut, MIN_SHARES_DELTA);
        }

        // Get outcome supply
        uint256 outcomeCurrentSupply = marketProxy.totalSupply(outcomeIdx);

        // Calculate exps
        // Note: No rounding, to not propagate error to future trades
        outcomeNewExp = market.config.b.outcomeExp(outcomeCurrentSupply + sharesOut);
        uint256 outcomeCurrentExp = market.config.b.outcomeExp(outcomeCurrentSupply);

        // Checks: Calculate & Validate new sum term
        // Note: calculate most accurate approximation (nor upper nor lower bound)
        newExpSum = market.expSum + outcomeNewExp - outcomeCurrentExp;
        assert(newExpSum > market.expSum);

        // Checks: Calculate & Validate exp sums
        // Note: Every operation is rounded against the user
        uint256 newExpSumUpperBound = newExpSum.getExpUpperBound();
        uint256 currentExpSumLowerBound = market.expSum.getExpLowerBound();
        assert(newExpSumUpperBound > currentExpSumLowerBound);

        // Checks: Calculate & Validate ratio
        // Note: Ceil the div to round against the user
        uint256 ratio = newExpSumUpperBound.mulDiv(1e18, currentExpSumLowerBound, Math.Rounding.Ceil);
        assert(ratio > 1e18);

        // Calculate the upper bound of ln of ratio (to round against the user)
        uint256 ratioLnUpperBound = ratio.computeLnUpperBound();

        // Checks: Calculate tokens in (with fee)
        // Note: To round against the user, we ceil the division
        uint256 netTokensIn = market.config.b.mulDiv(ratioLnUpperBound, 1e18 * TOKEN_DECIMAL_SCALER, Math.Rounding.Ceil);

        // Add trading fee to net tokens in
        (tokensIn,) = netTokensIn.addFee(market.config.tradingFee);

        // Checks: Validate tokens in
        if (tokensIn < MIN_TOKENS_DELTA) {
            revert TokensInBelowMinTokensDelta(tokensIn, MIN_TOKENS_DELTA);
        }
    }

    /// @inheritdoc ILmsrGateway
    function quoteSellExactIn(ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesIn)
        public
        view
        ifDeployedByFactory(marketProxy)
        ifOpen(marketProxy)
        returns (uint256 tokensOut, uint256 outcomeNewExp, uint256 newExpSum)
    {
        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Checks: Ensure outcome idx is valid
        if (outcomeIdx >= market.config.outcomeCount) {
            revert ILmsrMarketErrors.OutcomeIsOutOfBounds(outcomeIdx, market.config.outcomeCount);
        }

        // Checks: Ensure shares in is at least min shares delta
        if (sharesIn < MIN_SHARES_DELTA) {
            revert SharesInBelowMinDelta(sharesIn, MIN_SHARES_DELTA);
        }

        // Get outcome supply
        uint256 outcomeCurrentSupply = marketProxy.totalSupply(outcomeIdx);

        /// Checks: Ensure shares in does not exceed outcome supply
        if (sharesIn > outcomeCurrentSupply) {
            revert ILmsrMathErrors.SharesInExceedSupply(sharesIn, outcomeCurrentSupply);
        }

        // Calculate new supply
        uint256 outcomeNewSupply = outcomeCurrentSupply - sharesIn;

        // Checks: Ensure outcome new supply is either zero or at least min shares delta
        if (0 < outcomeNewSupply && outcomeNewSupply < MIN_SHARES_DELTA) {
            revert OutcomeNewSupplyBelowMinDelta(outcomeNewSupply, MIN_SHARES_DELTA);
        }

        // Calculate exps
        // Note: No rounding, to not propagate error to future trades
        outcomeNewExp = market.config.b.outcomeExp(outcomeNewSupply);
        uint256 outcomeCurrentExp = market.config.b.outcomeExp(outcomeCurrentSupply);

        // Calculate new sum term
        // Note: calculate most accurate approximation (nor upper nor lower bound)
        newExpSum = market.expSum + outcomeNewExp - outcomeCurrentExp;
        assert(newExpSum <= market.expSum); // Note: If new exp is greater, something weird is going on.
        if (newExpSum == market.expSum) {
            // Note: If new exp is not lower, the outcome exp calculation lost too much precision.
            revert ILmsrMathErrors.SellTooSmall();
        }

        // Calculate sum term bounds
        // Note: Every operation is rounded against the user
        uint256 currentExpSumLowerBound = market.expSum.getExpLowerBound();
        uint256 newExpSumUpperBound = newExpSum.getExpUpperBound();
        if (newExpSumUpperBound >= currentExpSumLowerBound) {
            revert ILmsrMathErrors.SellTooSmall();
        }

        // Calculate ratio
        // Note: instead of negating the log input (which causes numerical instability) and the output, flip the ratio
        // Note: Floor the div to round against the user
        uint256 ratio = currentExpSumLowerBound.mulDiv(1e18, newExpSumUpperBound, Math.Rounding.Floor);
        if (ratio <= 1e18) {
            revert ILmsrMathErrors.RatioTooSmall();
        }

        // Calculate lower bound of ln of ratio (to round against the user)
        uint256 ratioLnLowerBound = ratio.computeLnLowerBound();

        // Calculate tokens out (with fee)
        // Note: To round against the user, we floor the division
        uint256 grossTokensOut =
            market.config.b.mulDiv(ratioLnLowerBound, 1e18 * TOKEN_DECIMAL_SCALER, Math.Rounding.Floor);

        // Deduct trading fee from gross tokens out
        (tokensOut,) = grossTokensOut.deductFee(market.config.tradingFee);

        // Checks: Validate tokens out
        if (tokensOut < MIN_TOKENS_DELTA) {
            revert TokensOutBelowMinTokensDelta(tokensOut, MIN_TOKENS_DELTA);
        }
    }

    // Market Info

    /// @inheritdoc ILmsrGateway
    function marketCreator(ILmsrMarket marketProxy) external view ifDeployedByFactory(marketProxy) returns (address) {
        return marketProxy.marketCreator();
    }

    /// @inheritdoc ILmsrGateway
    function marketMetadata(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (IDelphiMarket.VerifiableUri memory)
    {
        return marketProxy.getMarketMetadata();
    }

    /// @inheritdoc ILmsrGateway
    function getMarket(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (ILmsrMarket.Market memory)
    {
        return marketProxy.getMarket();
    }

    /// @inheritdoc ILmsrGateway
    function marketStatus(ILmsrMarket marketProxy)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (ILmsrMarket.MarketStatus)
    {
        return marketProxy.marketStatus();
    }

    // Spot Prices

    /// @inheritdoc ILmsrGateway
    function spotPrice(ILmsrMarket marketProxy, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.spotPrice(outcomeIdx);
    }

    /// @inheritdoc ILmsrGateway
    function spotPrices(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.spotPrices(outcomeIndices);
    }

    // Spot Implied Probabilities

    /// @inheritdoc ILmsrGateway
    function spotImpliedProbability(ILmsrMarket marketProxy, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.spotImpliedProbability(outcomeIdx);
    }

    /// @inheritdoc ILmsrGateway
    function spotImpliedProbabilities(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.spotImpliedProbabilities(outcomeIndices);
    }

    // Supplies

    /// @inheritdoc ILmsrGateway
    function totalSupply(ILmsrMarket marketProxy, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.totalSupply(outcomeIdx);
    }

    /// @inheritdoc ILmsrGateway
    function totalSupplies(ILmsrMarket marketProxy, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.totalSupplies(outcomeIndices);
    }

    // Balances

    /// @inheritdoc ILmsrGateway
    function balanceOf(ILmsrMarket marketProxy, address owner, uint256 outcomeIdx)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.balanceOf(owner, outcomeIdx);
    }

    /// @inheritdoc ILmsrGateway
    function batchBalanceOf(ILmsrMarket marketProxy, address[] calldata owners, uint256[] calldata outcomeIndices)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256[] memory)
    {
        return marketProxy.batchBalanceOf(owners, outcomeIndices);
    }

    /// @inheritdoc ILmsrGateway
    function allowance(ILmsrMarket marketProxy, address owner, address spender, uint256 id)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (uint256)
    {
        return marketProxy.allowance(owner, spender, id);
    }

    /// @inheritdoc ILmsrGateway
    function isOperator(ILmsrMarket marketProxy, address operator, address spender)
        external
        view
        ifDeployedByFactory(marketProxy)
        returns (bool)
    {
        return marketProxy.isOperator(operator, spender);
    }

    // ========== INTERNAL FUNCTIONS ==========

    /// @dev Validates that the gateway is initialized and the market proxy was deployed by the factory.
    /// @param marketProxy The market proxy to validate.
    function _ifDeployedByFactory(ILmsrMarket marketProxy) internal view {
        if (_getInitializedVersion() == 0) {
            revert GatewayNotInitialized();
        }

        if (!delphiFactory.marketProxyExists(address(marketProxy))) {
            revert MarketProxyNotDeployedByFactory(address(marketProxy));
        }
    }

    function _ifOpen(ILmsrMarket marketProxy) internal view {
        if (marketProxy.marketStatus() != ILmsrMarketTypes.MarketStatus.OPEN) {
            revert MarketNotOpen();
        }
    }

    function _onlyOracleRelayer() internal view {
        if (msg.sender != oracleRelayer) revert CallerIsNotOracleRelayer(msg.sender);
    }
}
