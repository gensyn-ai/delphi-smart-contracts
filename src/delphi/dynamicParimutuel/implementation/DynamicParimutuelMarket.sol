// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "./IDynamicParimutuelMarket.sol";
import {ERC6909TokenSupply, ERC6909} from "@openzeppelin/contracts/token/ERC6909/extensions/ERC6909TokenSupply.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Libraries
import {DynamicParimutuelMath} from "src/delphi/dynamicParimutuel/math/DynamicParimutuelMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces
import {IDynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGateway.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";

/// @title DynamicParimutuelMarket
/// @notice Implementation of a dynamic parimutuel prediction market using an ERC6909 multi-token for outcome shares.
/// @dev Deployed once. Will be cloned several times by proxies deployed by the Delphi factory. State changing functions are only callable by the Gateway contract.
///      The pricing model uses a square root of sum-of-squares invariant scaled by a liquidity depth parameter (k).
contract DynamicParimutuelMarket is
    IDelphiMarket,
    IDynamicParimutuelMarket,
    ERC6909TokenSupply,
    Initializable,
    ReentrancyGuard
{
    // ===== CONSTANTS =====
    uint256 public constant override MIN_OUTCOME_COUNT = 2;
    uint256 public constant override MAX_OUTCOME_COUNT = 20;
    uint256 public constant override MIN_K = 1e18; // 1
    uint256 public constant override MAX_K = 100e18; // 100
    uint256 public constant override MIN_TRADING_FEE = 0.005e18; // 0.5%
    uint256 public constant override MAX_TRADING_FEE = 0.05e18; // 5%
    uint256 public constant override MIN_TRADING_WINDOW = 2 minutes;
    uint256 public constant override MAX_TRADING_WINDOW = 365 days;
    uint256 public constant override MIN_SETTLEMENT_WINDOW = 1 hours;
    uint256 public constant override MAX_SETTLEMENT_WINDOW = 24 hours;
    uint256 public constant override MIN_TRADING_FEES_RECIPIENT_PCT = 0; // 0%
    uint256 public constant override MAX_TRADING_FEES_RECIPIENT_PCT = 1e18; // 100%
    uint256 internal constant _MIN_INITIAL_DEPOSIT_18 = 1e18;
    uint256 internal constant _MAX_INITIAL_DEPOSIT_18 = 1_000_000e18;

    // ===== IMMUTABLES =====
    address public immutable override GATEWAY;
    IERC20Metadata public immutable override TOKEN;
    address public immutable override TRADING_FEES_RECIPIENT;
    uint256 public immutable override TRADING_FEES_RECIPIENT_PCT;
    uint256 public immutable override TOKEN_DECIMAL_SCALER;
    uint256 public immutable override MIN_INITIAL_DEPOSIT;
    uint256 public immutable override MAX_INITIAL_DEPOSIT;

    // ===== INITIALIZATION IMMUTABLES =====

    /// @inheritdoc IDynamicParimutuelMarket
    address public override marketCreator;
    VerifiableUri private _marketMetadata;

    // ===== STATE VARIABLES =====
    Market internal _market;
    /// @inheritdoc IDynamicParimutuelMarket
    uint256 public override marketCreatorSharesPerOutcome;
    /// @inheritdoc IDynamicParimutuelMarket
    uint256 public override outcomeSuppliesSum;
    /// @inheritdoc IDynamicParimutuelMarket
    bool public override marketCreationSharesLiquidated;

    // ===== LIBRARIES =====
    using DynamicParimutuelMath for uint256;
    using SafeERC20 for IERC20Metadata;

    // ===== MODIFIERS =====

    /// @dev Reverts if the caller is not the gateway contract.
    modifier onlyGateway() {
        _onlyGateway();
        _;
    }

    /// @dev Reverts if the market is not in the required status.
    modifier ifStatus(MarketStatus requiredStatus) {
        _ifStatus(requiredStatus);
        _;
    }

    /// @dev Reverts if the outcome index is out of bounds.
    modifier validOutcomeIdx(uint256 outcomeIdx) {
        _validOutcomeIdx(outcomeIdx);
        _;
    }

    // ===== CONSTRUCTOR =====

    /// @notice Deploys the market implementation with a configuration that will be shared by all of its proxies.
    /// @dev Disables initializers to prevent direct initialization of the implementation contract.
    /// @param tradingFeesRecipient The address that receives a portion of trading fees.
    /// @param gateway The gateway contract address.
    /// @param tradingFeesRecipientPct The percentage of fees sent to the recipient (18 decimal fixed-point).
    constructor(address tradingFeesRecipient, address gateway, uint256 tradingFeesRecipientPct) {
        // Checks: Validate input addresses
        if (tradingFeesRecipient == address(0)) {
            revert ZeroTradingFeesRecipientAddress();
        }
        if (gateway == address(0)) {
            revert ZeroGatewayAddress();
        }

        // Checks: Validate tradingFeesRecipientPct
        if (tradingFeesRecipientPct < MIN_TRADING_FEES_RECIPIENT_PCT) {
            revert TradingFeesRecipientPctTooLow(tradingFeesRecipientPct, MIN_TRADING_FEES_RECIPIENT_PCT);
        }
        if (tradingFeesRecipientPct > MAX_TRADING_FEES_RECIPIENT_PCT) {
            revert TradingFeesRecipientPctTooHigh(tradingFeesRecipientPct, MAX_TRADING_FEES_RECIPIENT_PCT);
        }

        // Effects: Set addresses
        TRADING_FEES_RECIPIENT = tradingFeesRecipient;
        GATEWAY = gateway;

        // Effects: Set trading fees recipient pct
        TRADING_FEES_RECIPIENT_PCT = tradingFeesRecipientPct;

        // Effects: Set token and scaler
        TOKEN = IDynamicParimutuelGateway(gateway).TOKEN();
        TOKEN_DECIMAL_SCALER = IDynamicParimutuelGateway(gateway).TOKEN_DECIMAL_SCALER();

        // Effects: Set initial deposit bounds
        MIN_INITIAL_DEPOSIT = _MIN_INITIAL_DEPOSIT_18 / TOKEN_DECIMAL_SCALER;
        MAX_INITIAL_DEPOSIT = _MAX_INITIAL_DEPOSIT_18 / TOKEN_DECIMAL_SCALER;

        // Effects: Disable initializations in this contract (can only be initialized through a proxy)
        _disableInitializers();
    }

    // ===== INITIALIZER =====

    /// @notice Initializes a new market proxy (with its own unique configuration).
    /// @dev Will be delegatecalled by proxy. Determines per-market state. Can only be called once.
    /// @param marketCreator_ The address of the market creator.
    /// @param initialDeposit_ The initial deposit deposited by the creator.
    /// @param newMarketMetadata_ The verifiable URI for market metadata.
    /// @param initializationCalldata_ ABI-encoded MarketConfig struct.
    function initialize(
        address marketCreator_,
        uint256 initialDeposit_,
        VerifiableUri calldata newMarketMetadata_,
        bytes calldata initializationCalldata_
    ) external nonReentrant initializer {
        // Decode initialization calldata
        MarketConfig memory newMarketConfig_ = abi.decode(initializationCalldata_, (MarketConfig));

        // Checks: Validate market creator
        if (address(marketCreator_) == address(0)) {
            revert ZeroMarketCreatorAddress();
        }

        // Checks: Validate new market config
        _validateDynamicParimutuelConfig(newMarketConfig_);

        // Checks: Validate new market metadata
        _validateVerifiableUri(newMarketMetadata_);

        // Checks: Validate initial deposit
        if (initialDeposit_ < MIN_INITIAL_DEPOSIT) {
            revert InitialDepositTooLow(initialDeposit_, MIN_INITIAL_DEPOSIT);
        }
        if (initialDeposit_ > MAX_INITIAL_DEPOSIT) {
            revert InitialDepositTooHigh(initialDeposit_, MAX_INITIAL_DEPOSIT);
        }

        // Calculate shares per outcome
        marketCreatorSharesPerOutcome = newMarketConfig_.k
            .sharesPerOutcomeAtMarketCreation({
                outcomeCount: newMarketConfig_.outcomeCount,
                initialDeposit: initialDeposit_,
                tokenDecimalScalar: TOKEN_DECIMAL_SCALER
            });
        assert(marketCreatorSharesPerOutcome > 0);

        // Calculate initial pool
        uint256 initialPool = initialDeposit_.initialPool(newMarketConfig_.outcomeCount);
        assert(initialPool > 0);

        // Checks: Ensure market is properly funded
        uint256 tokenBalance = TOKEN.balanceOf(address(this));
        if (tokenBalance < initialDeposit_) {
            revert MarketNotProperlyFunded(tokenBalance, initialDeposit_);
        }

        // Effects: Set initialization immutables
        marketCreator = marketCreator_;
        _marketMetadata = newMarketMetadata_;

        uint256 sumTerm36 = (marketCreatorSharesPerOutcome ** 2) * newMarketConfig_.outcomeCount;
        assert(sumTerm36 > 0);

        // Effects: Save new market
        _market = Market({
            config: newMarketConfig_,
            initialPool: initialPool,
            pool: initialPool,
            tradingFees: 0,
            refund: tokenBalance - initialPool,
            sumTerm36: sumTerm36,
            winningOutcomeIdx: type(uint256).max // Note: Sentinel value for "no winner yet"
        });

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < newMarketConfig_.outcomeCount; outcomeIdx++) {
            // Effects: Mint market creator shares per outcome
            /**
             * Note:
             * To ensure the market creator has "skin in the game", these shares should be locked in the contract until settlement/liquidation.
             * Therefore, they are minted to address(this), instead of to the market creator.
             */
            _mint(address(this), outcomeIdx, marketCreatorSharesPerOutcome);
        }
    }

    // ===== EXTERNAL FUNCTIONS =====

    /// @inheritdoc IDynamicParimutuelMarket
    function buy(address buyer, uint256 outcomeIdx, uint256 tokensIn, uint256 sharesOut)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.OPEN)
    {
        // Deduct trading fee from tokens in
        (uint256 netTokensIn, uint256 feeAmount) = tokensIn.deductFee(_market.config.tradingFee);

        // Checks: Validate buy
        (uint256 newSumTerm36, bool valid) = _market.config.k
            .buyIsValid({
                currentSumTerm36: _market.sumTerm36,
                modelCurrentSupply: totalSupply(outcomeIdx),
                tokensIn: netTokensIn,
                sharesOut: sharesOut,
                tokenDecimalScalar: TOKEN_DECIMAL_SCALER
            });
        if (!valid) {
            revert InvalidBuy();
        }

        // Effects: Update market
        _market.sumTerm36 = newSumTerm36;
        _market.pool += netTokensIn;
        _market.tradingFees += feeAmount;

        // Effects: Mint entry shares to buyer
        _mint(buyer, outcomeIdx, sharesOut);

        // Effects: Emit event
        emit Buy(buyer, outcomeIdx, tokensIn, sharesOut);

        // Interactions: Pull tokens to seller
        TOKEN.safeTransferFrom(buyer, address(this), tokensIn);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function sell(address seller, uint256 outcomeIdx, uint256 sharesIn, uint256 tokensOut)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.OPEN)
    {
        // Add trading fee to tokens out
        (uint256 grossTokensOut, uint256 feeAmount) = tokensOut.addFee(_market.config.tradingFee);

        // Checks: Ensure pool can cover gross tokens out (tokens out + fee)
        if (grossTokensOut > _market.pool) {
            revert GrossTokensOutExceedMarketPool(grossTokensOut, _market.pool);
        }

        // Checks: Validate sell
        (uint256 newSumTerm36, bool valid) = _market.config.k
            .sellIsValid({
                currentSumTerm36: _market.sumTerm36,
                modelCurrentSupply: totalSupply(outcomeIdx),
                sharesIn: sharesIn,
                tokensOut: grossTokensOut,
                tokenDecimalScalar: TOKEN_DECIMAL_SCALER
            });
        if (!valid) {
            revert InvalidSell();
        }

        // Effects: Update market
        _market.sumTerm36 = newSumTerm36;
        _market.pool -= grossTokensOut;
        _market.tradingFees += feeAmount;

        // Effects: Burn entry shares from seller
        _burn(seller, outcomeIdx, sharesIn);

        // Effects: Emit event
        emit Sell(seller, outcomeIdx, sharesIn, tokensOut);

        // Interactions: Push tokens to seller
        TOKEN.safeTransfer(seller, tokensOut);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function submitWinner(address caller, uint256 winningOutcomeIdx)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.AWAITING_SETTLEMENT)
        returns (uint256 marketCreatorReward, uint256 refund, uint256 marketCreatorTradingFeesCut)
    {
        // Checks: Validate
        // Note: the winningOutcomeIdx is validated in the `totalSupply` view
        if (caller != marketCreator) {
            revert CallerNotMarketCreator(caller, marketCreator);
        }

        // Cache trading fee
        uint256 tradingFees = _market.tradingFees;
        uint256 _refund = _market.refund;

        // Calculate market creator reward
        uint256 _marketCreatorReward = marketCreatorWinningSharesSettlementValue(winningOutcomeIdx);

        // Effects: Update market
        _market.winningOutcomeIdx = winningOutcomeIdx;
        _market.pool -= _marketCreatorReward;
        _market.tradingFees = 0;
        _market.refund = 0;

        // Calculate trading fees recipient cut
        uint256 tradingFeesRecipientCut =
            tradingFees.tradingFeesRecipientCut({tradingFeesRecipientPct: TRADING_FEES_RECIPIENT_PCT});
        uint256 _marketCreatorTradingFeesCut = tradingFees - tradingFeesRecipientCut;

        // Effects: Emit event
        emit WinnerSubmitted(winningOutcomeIdx, _marketCreatorReward, _refund, _marketCreatorTradingFeesCut);

        // Interactions: Give tradingFeesRecipientCut to TRADING_FEES_RECIPIENT
        TOKEN.safeTransfer(TRADING_FEES_RECIPIENT, tradingFeesRecipientCut);

        // Interactions: Give market creator tokens
        uint256 marketCreatorTotal = _marketCreatorReward + _refund + _marketCreatorTradingFeesCut;
        TOKEN.safeTransfer(marketCreator, marketCreatorTotal);

        return (_marketCreatorReward, _refund, _marketCreatorTradingFeesCut);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function redeem(address redeemer)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.SETTLED)
        returns (uint256 sharesIn, uint256 tokensOut)
    {
        // Get redeemer winning shares
        sharesIn = balanceOf(redeemer, _market.winningOutcomeIdx);

        // Checks: Validate sharesIn
        if (sharesIn == 0) {
            revert RedeemZeroShares();
        }

        // Get unclaimed shares
        uint256 unclaimedShares =
            totalSupply(_market.winningOutcomeIdx) - balanceOf(address(this), _market.winningOutcomeIdx);

        // Calculate tokens out
        tokensOut = _market.pool.redeemerReward({redeemerWinningShares: sharesIn, unclaimedShares: unclaimedShares});

        // Checks: Validate tokens out
        if (tokensOut == 0) {
            revert RedeemZeroTokensOut();
        }

        // Effects: Pull winning outcome shares from the redeemer
        _transfer({from: redeemer, to: address(this), id: _market.winningOutcomeIdx, amount: sharesIn});

        // Effects: Update market pool
        _market.pool -= tokensOut;

        // Effects: Emit event
        emit Redemption({redeemer: redeemer, sharesIn: sharesIn, tokensOut: tokensOut});

        // Interactions: Push tokens out
        TOKEN.safeTransfer(redeemer, tokensOut);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function liquidate(address liquidator, uint256[] calldata outcomeIndices)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.EXPIRED)
        returns (uint256[] memory sharesIn, uint256 totalTokensOut)
    {
        // Checks: Ensure outcomeIndices isn't empty
        if (outcomeIndices.length == 0) {
            revert EmptyOutcomeIndices();
        }

        // If market creation shares haven't been liquidated
        if (!marketCreationSharesLiquidated) {
            // Effects/Interactions: Liquidate market creation shares
            _liquidateMarketCreationShares();
        }

        // Effects: Initialize array lengths
        sharesIn = new uint256[](outcomeIndices.length);

        // Initialize sum var
        uint256 numeratorSum36 = 0;

        // For each outcome index
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            // Get outcome index
            uint256 outcomeIdx = outcomeIndices[i];

            // Get liquidator shares
            uint256 _sharesIn = balanceOf(liquidator, outcomeIdx);

            // Checks: Validate sharesIn
            if (_sharesIn == 0) {
                revert ZeroSharesIn();
            }

            // Update shares in array
            sharesIn[i] = _sharesIn;

            // Update sum var
            numeratorSum36 += _sharesIn * totalSupply(outcomeIdx);

            // Effects: Pull outcome shares (don't burn them, to keep the prices frozen)
            // Note: Do not burn, to keep liquidations order-independent
            _transfer({from: liquidator, to: address(this), id: outcomeIdx, amount: _sharesIn});
        }

        // Calculate total tokens out
        totalTokensOut = _market.config.k
            .liquidatorTotalReward({
                numeratorSum: numeratorSum36 / 1e18,
                currentSumTerm36: _market.sumTerm36,
                tokenDecimalScalar: TOKEN_DECIMAL_SCALER
            });

        // Effects: Update market pool
        _market.pool -= totalTokensOut;

        // Effects: Emit event
        emit Liquidation({
            liquidator: liquidator, outcomeIndices: outcomeIndices, sharesIn: sharesIn, totalTokensOut: totalTokensOut
        });

        // Interactions: Push tokens out
        TOKEN.safeTransfer(liquidator, totalTokensOut);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function liquidateMarketCreationShares()
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.EXPIRED)
        returns (uint256 _totalTokensOut)
    {
        if (marketCreationSharesLiquidated) {
            revert MarketCreationSharesAlreadyLiquidated();
        }
        return _liquidateMarketCreationShares();
    }

    // ===== EXTERNAL VIEW FUNCTIONS =====

    /// @inheritdoc IDelphiMarket
    function getMarketMetadata() external view returns (VerifiableUri memory) {
        return _marketMetadata;
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function getMarket() external view returns (Market memory) {
        return _market;
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function marketStatus() public view returns (MarketStatus) {
        if (block.timestamp <= _market.config.tradingDeadline) {
            return MarketStatus.OPEN;
        }

        if (_market.winningOutcomeIdx != type(uint256).max) {
            return MarketStatus.SETTLED;
        }

        if (block.timestamp <= _market.config.settlementDeadline) {
            return MarketStatus.AWAITING_SETTLEMENT;
        }

        return MarketStatus.EXPIRED;
    }

    /*
     * Note: THE `validOutcomeIdx` MODIFIER IS CRITICAL HERE, AS IT PROTECTS:
     * - The quoteBuyExactOut/quoteSellExactIn views (in the gateway)
     * - The buyExactOut/sellExactIn functions (in the gateway)
     * - The spotPrice/spotImpliedProbability/totalSupply views (in the gateway)
     * - The buy/sell/submitWinner/liquidate functions (in the market)
     * - The spotPrice/spotImpliedProbability views (in the market)
     * DO NOT REMOVE OR MODIFY WITHOUT FULLY UNDERSTANDING THE IMPLICATIONS.
    */
    /// @inheritdoc IDynamicParimutuelMarket
    function totalSupply(uint256 outcomeIdx)
        public
        view
        override(ERC6909TokenSupply, IDynamicParimutuelMarket)
        validOutcomeIdx(outcomeIdx)
        returns (uint256)
    {
        return super.totalSupply(outcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function totalSupplies(uint256[] calldata outcomeIndices) external view returns (uint256[] memory supplies) {
        supplies = new uint256[](outcomeIndices.length);
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            supplies[i] = totalSupply(outcomeIndices[i]);
        }
    }

    /*
     * Note: THE `validOutcomeIdx` MODIFIER IS IMPORTANT HERE, AS IT PROTECTS:
     * - The submitWinner/redeem/liquidate functions (in the market)
     * DO NOT REMOVE OR MODIFY WITHOUT FULLY UNDERSTANDING THE IMPLICATIONS.
    */
    /// @inheritdoc IDynamicParimutuelMarket
    function balanceOf(address owner, uint256 outcomeIdx)
        public
        view
        override(ERC6909, IDynamicParimutuelMarket, IERC6909)
        validOutcomeIdx(outcomeIdx)
        returns (uint256)
    {
        return super.balanceOf(owner, outcomeIdx);
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function batchBalanceOf(address[] calldata owners, uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory balances)
    {
        if (owners.length != outcomeIndices.length) {
            revert ArrayLengthMismatch(owners.length, outcomeIndices.length);
        }
        balances = new uint256[](owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            balances[i] = balanceOf(owners[i], outcomeIndices[i]);
        }
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function spotPrice(uint256 outcomeIdx) public view validOutcomeIdx(outcomeIdx) returns (uint256) {
        return _market.config.k
            .spotPrice({
                outcomeSupply: totalSupply(outcomeIdx),
                currentSumTerm36: _market.sumTerm36,
                tokenDecimalScalar: TOKEN_DECIMAL_SCALER
            });
    }

    /// @inheritdoc IDynamicParimutuelMarket
    // Note: Do not use the math library directly (or the validOutcomeIdx check will be bypassed)
    function spotPrices(uint256[] calldata outcomeIndices) external view returns (uint256[] memory prices) {
        prices = new uint256[](outcomeIndices.length);
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            prices[i] = spotPrice(outcomeIndices[i]);
        }
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function spotImpliedProbability(uint256 outcomeIdx) public view validOutcomeIdx(outcomeIdx) returns (uint256) {
        return totalSupply(outcomeIdx).spotImpliedProbability({currentSumTerm36: _market.sumTerm36});
    }

    /// @inheritdoc IDynamicParimutuelMarket
    // Note: Do not use the math library directly (or the validOutcomeIdx check will be bypassed)
    function spotImpliedProbabilities(uint256[] calldata outcomeIndices)
        external
        view
        returns (uint256[] memory impliedProbabilities)
    {
        impliedProbabilities = new uint256[](outcomeIndices.length);
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            impliedProbabilities[i] = spotImpliedProbability(outcomeIndices[i]);
        }
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function marketCreatorWinningSharesSettlementValue(uint256 winningOutcomeIdx)
        public
        view
        returns (uint256 tokensOut)
    {
        return _market.pool
            .redeemerReward({
                redeemerWinningShares: marketCreatorSharesPerOutcome, unclaimedShares: totalSupply(winningOutcomeIdx)
            });
    }

    /// @inheritdoc IDynamicParimutuelMarket
    function marketCreatorTotalSharesLiquidationValue() public view returns (uint256 tokensOut) {
        return _market.config.k
            .liquidatorTotalReward({
                numeratorSum: outcomeSuppliesSum.mulDivDown(marketCreatorSharesPerOutcome, 1e18), // Note: round down (against user)
                currentSumTerm36: _market.sumTerm36,
                tokenDecimalScalar: TOKEN_DECIMAL_SCALER
            });
    }

    // ===== INTERNAL FUNCTIONS ====

    /// @dev Overrides ERC6909 _update to track the sum of all outcome supplies.
    /// @param from The sender address (address(0) for minting).
    /// @param to The recipient address (address(0) for burning).
    /// @param id The outcome index.
    /// @param amount The amount of shares transferred.
    function _update(address from, address to, uint256 id, uint256 amount) internal override {
        // Update
        super._update(from, to, id, amount);

        // If minting
        if (from == address(0)) {
            // Increase sum of outcome supplies
            outcomeSuppliesSum += amount;

            // If burning
        } else if (to == address(0)) {
            // Decrease sum of outcome supplies
            outcomeSuppliesSum -= amount;
        }
    }

    /// @dev Liquidates the market creator's initial shares and sends the proceeds plus the accrued trading fees to the trading-fees recipient.
    /// @return tokensOut The total tokens sent to the trading-fees recipient.
    function _liquidateMarketCreationShares() internal returns (uint256 tokensOut) {
        // Checks: Ensure market creation shares haven't already been liquidated
        assert(!marketCreationSharesLiquidated);

        // Effects: Mark market creation shares as liquidated
        marketCreationSharesLiquidated = true;

        // Get vars
        uint256 liquidationValue = marketCreatorTotalSharesLiquidationValue();
        uint256 tradingFees = _market.tradingFees;
        uint256 refund = _market.refund;

        // Effects: Update market
        _market.pool -= liquidationValue;
        _market.tradingFees = 0;
        _market.refund = 0;

        // Interactions: Send  to TRADING_FEES_RECIPIENT
        uint256 totalValue = liquidationValue + tradingFees + refund;
        TOKEN.safeTransfer(TRADING_FEES_RECIPIENT, totalValue);

        // Return
        return totalValue;
    }

    // ===== INTERNAL VIEW FUNCTIONS ====

    /// @dev Validates all fields of a MarketConfig struct against the allowed bounds.
    /// @param config The market configuration to validate.
    function _validateDynamicParimutuelConfig(MarketConfig memory config) internal view {
        // Validate outcome count
        if (config.outcomeCount < MIN_OUTCOME_COUNT) {
            revert OutcomeCountTooLow(config.outcomeCount, MIN_OUTCOME_COUNT);
        }
        if (config.outcomeCount > MAX_OUTCOME_COUNT) {
            revert OutcomeCountTooHigh(config.outcomeCount, MAX_OUTCOME_COUNT);
        }

        // Validate k
        if (config.k < MIN_K) {
            revert KTooLow(config.k, MIN_K);
        }
        if (config.k > MAX_K) {
            revert KTooHigh(config.k, MAX_K);
        }

        // Validate trading fee
        if (config.tradingFee < MIN_TRADING_FEE) {
            revert TradingFeeTooLow(config.tradingFee, MIN_TRADING_FEE);
        }
        if (config.tradingFee > MAX_TRADING_FEE) {
            revert TradingFeeTooHigh(config.tradingFee, MAX_TRADING_FEE);
        }

        // Validate trading window
        if (config.tradingDeadline <= block.timestamp) {
            revert TradingDeadlineNotInFuture(config.tradingDeadline, block.timestamp);
        }
        uint256 tradingWindow = config.tradingDeadline - block.timestamp;
        if (tradingWindow < MIN_TRADING_WINDOW) {
            revert TradingWindowTooShort(tradingWindow, MIN_TRADING_WINDOW);
        }
        if (tradingWindow > MAX_TRADING_WINDOW) {
            revert TradingWindowTooLong(tradingWindow, MAX_TRADING_WINDOW);
        }

        // Validate settlement window
        if (config.settlementDeadline <= config.tradingDeadline) {
            revert SettlementDeadlineBeforeTradingDeadline(config.settlementDeadline, config.tradingDeadline);
        }
        uint256 settlementWindow = config.settlementDeadline - config.tradingDeadline;
        if (settlementWindow < MIN_SETTLEMENT_WINDOW) {
            revert SettlementWindowTooShort(settlementWindow, MIN_SETTLEMENT_WINDOW);
        }
        if (settlementWindow > MAX_SETTLEMENT_WINDOW) {
            revert SettlementWindowTooLong(settlementWindow, MAX_SETTLEMENT_WINDOW);
        }
    }

    /// @dev Reverts if the caller is not the gateway.
    function _onlyGateway() internal view {
        if (msg.sender != GATEWAY) {
            revert CallerNotGateway(msg.sender);
        }
    }

    /// @dev Reverts if the outcome index is out of bounds for the market.
    /// @param outcomeIdx The outcome index to validate.
    function _validOutcomeIdx(uint256 outcomeIdx) internal view {
        if (outcomeIdx >= _market.config.outcomeCount) {
            revert WinningOutcomeOutOfBounds(outcomeIdx, _market.config.outcomeCount);
        }
    }

    /// @dev Reverts if the market is not in the required status.
    /// @param requiredStatus The expected market status.
    function _ifStatus(MarketStatus requiredStatus) internal view {
        IDynamicParimutuelMarket.MarketStatus _marketStatus = marketStatus();
        if (_marketStatus != requiredStatus) {
            revert WrongMarketStatus(_marketStatus, requiredStatus);
        }
    }

    // ===== INTERNAL PURE FUNCTIONS ====

    /// @dev Ensures that a VerifiableUri has no empty fields.
    /// @param verifiableUri The URI to validate.
    function _validateVerifiableUri(VerifiableUri calldata verifiableUri) internal pure {
        if (bytes(verifiableUri.uri).length == 0) {
            revert EmptyUri();
        }
        if (verifiableUri.uriContentHash == bytes32(0)) {
            revert EmptyUriContentHash();
        }
    }
}
