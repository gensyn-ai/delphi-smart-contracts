// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {ILmsrMarket} from "./ILmsrMarket.sol";
import {ERC6909TokenSupply, ERC6909} from "@openzeppelin/contracts/token/ERC6909/extensions/ERC6909TokenSupply.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC6909} from "@openzeppelin/contracts/interfaces/IERC6909.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";

/// @title LmsrMarket
/// @notice Implementation of an lmsr prediction market using an ERC6909 multi-token for outcome shares.
/// @dev Deployed once. Will be cloned several times by proxies deployed by the Delphi factory.
///      All LMSR state-transition functions (buy, sell, settleMarket, failMarket, transferKeeperFee,
///      redeem, liquidate, trySweep) are only callable by the Gateway contract. The inherited ERC-6909
///      share functions (transfer, transferFrom, approve, setOperator) are intentionally permissionless —
///      outcome shares are freely transferable, except to the market itself.
contract LmsrMarket is IDelphiMarket, ILmsrMarket, ERC6909TokenSupply, Initializable, ReentrancyGuard {
    // ===== CONSTANTS =====
    uint256 public constant override MIN_OUTCOME_COUNT = 2;
    uint256 public constant override MAX_OUTCOME_COUNT = 20;
    uint256 public constant override MIN_B = 1e18; // 1
    uint256 public constant override MAX_B = 5_000_000e18; // 5M
    uint256 public constant override MIN_TRADING_FEE = 0.005e18; // 0.5%
    uint256 public constant override MAX_TRADING_FEE = 0.05e18; // 5%
    uint256 public constant override MIN_TRADING_WINDOW = 30 seconds;
    uint256 public constant override MAX_TRADING_WINDOW = 10 * 365 days; // 10 years
    uint256 public constant override MIN_RESOLVE_DELAY = 15 minutes;
    uint256 public constant override MAX_RESOLVE_DELAY = 7 days;
    uint256 public constant override MIN_SETTLEMENT_WINDOW = 30 seconds;
    uint256 public constant override MAX_SETTLEMENT_WINDOW = 10 * 365 days; // 10 years
    uint256 public constant override MIN_TRADING_FEES_RECIPIENT_PCT = 0; // 0%
    uint256 public constant override MAX_TRADING_FEES_RECIPIENT_PCT = 1e18; // 100%

    // ===== IMMUTABLES =====
    address public immutable override GATEWAY;
    IERC20Metadata public immutable override TOKEN;
    address public immutable override TRADING_FEES_RECIPIENT;
    uint256 public immutable override TRADING_FEES_RECIPIENT_PCT;
    uint256 public immutable override TOKEN_DECIMAL_SCALER;
    uint256 public immutable override KEEPER_FEE;
    uint256 public immutable override ORACLE_FEE;

    // ===== INITIALIZATION IMMUTABLES =====

    /// @inheritdoc ILmsrMarket
    address public override marketCreator;
    VerifiableUri private _marketMetadata;

    // ===== STATE VARIABLES =====
    Market internal _market;
    /// @inheritdoc ILmsrMarket
    uint256 public override createdAt;
    /// @inheritdoc ILmsrMarket
    bool public override marketFailed;
    /// @inheritdoc ILmsrMarket
    bool public override keeperFeePaid;
    /// @inheritdoc ILmsrMarket
    bool public override oracleFeePaid;
    /// @inheritdoc ILmsrMarket
    bool public override losingPayoutSwept;
    /// @inheritdoc ILmsrMarket
    uint256 public override marketCreatorClaimable;

    // ===== LIBRARIES =====
    using LmsrMath for uint256;
    using SafeERC20 for IERC20Metadata;
    using Math for uint256;

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
    constructor(
        address tradingFeesRecipient,
        address gateway,
        uint256 tradingFeesRecipientPct,
        uint256 keeperFee,
        uint256 oracleFee
    ) {
        // Checks: Validate input addresses
        if (tradingFeesRecipient == address(0)) {
            revert TradingFeesRecipientIsZeroAddress();
        }
        if (gateway == address(0)) {
            revert GatewayIsZeroAddress();
        }

        // Checks: Validate tradingFeesRecipientPct
        if (tradingFeesRecipientPct < MIN_TRADING_FEES_RECIPIENT_PCT) {
            revert TradingFeesRecipientPctIsTooLow(tradingFeesRecipientPct, MIN_TRADING_FEES_RECIPIENT_PCT);
        }
        if (tradingFeesRecipientPct > MAX_TRADING_FEES_RECIPIENT_PCT) {
            revert TradingFeesRecipientPctIsTooHigh(tradingFeesRecipientPct, MAX_TRADING_FEES_RECIPIENT_PCT);
        }

        // Effects: Set addresses
        TRADING_FEES_RECIPIENT = tradingFeesRecipient;
        GATEWAY = gateway;

        // Effects: Set trading fees recipient pct
        TRADING_FEES_RECIPIENT_PCT = tradingFeesRecipientPct;

        // Effects: Set token and scaler
        TOKEN = ILmsrGateway(gateway).TOKEN();
        TOKEN_DECIMAL_SCALER = ILmsrGateway(gateway).TOKEN_DECIMAL_SCALER();

        // Effects: Set keeper and oracle fees
        /* Note: In the DelphiFactory:
         * - The MARKET_CREATION_FEE must be <= 100
         * - The MARKET_CREATION_FEE must be >= SETTLEMENT_FEES (KEEPER_FEE + ORACLE_FEE)
         * But if KEEPER_FEE + ORACLE_FEE > 100, this creates an impossible condition.
         * However, we consider this to be low severity, as its Gensyn controlled, and it'd only cause the factory deployment to revert.
         */
        KEEPER_FEE = keeperFee;
        ORACLE_FEE = oracleFee;

        // Effects: Disable initializations in this contract (can only be initialized through a proxy)
        _disableInitializers();
    }

    // ===== INITIALIZER =====

    /// @notice Initializes a new market proxy (with its own unique configuration).
    /// @dev Will be delegatecalled by proxy. Determines per-market state. Can only be called once.
    /// @param marketCreator_ The address of the market creator.
    /// @param newMarketConfig_ The market configuration.
    /// @param newMarketMetadata_ The verifiable URI for market metadata.
    function initialize(
        address marketCreator_,
        ILmsrMarketTypes.MarketConfig calldata newMarketConfig_,
        VerifiableUri calldata newMarketMetadata_
    ) external nonReentrant initializer {
        // Checks: Validate market creator
        if (address(marketCreator_) == address(0)) {
            revert MarketCreatorIsZeroAddress();
        }

        // Checks: Ensure the gateway has an oracle relayer wired before a market can be created.
        // Otherwise the market could only ever expire — resolveMarket would revert OracleRelayerNotSet
        // on the gateway — stranding it (and forcing pro-rata liquidation) until settlementDeadline.
        // Closing the race here makes it atomic with creation.
        if (ILmsrGateway(GATEWAY).oracleRelayer() == address(0)) {
            revert GatewayOracleRelayerNotSet();
        }

        // Checks: Validate new market config
        _validateLmsrConfig(newMarketConfig_);

        // Checks: Validate new market metadata
        _validateVerifiableUri(newMarketMetadata_);

        // Calculate max loss
        uint256 _maxLoss = maxLoss(newMarketConfig_.b, newMarketConfig_.outcomeCount);

        // Get token balance
        uint256 tokenBalance = TOKEN.balanceOf(address(this));

        // Checks: Ensure market is properly funded
        if (tokenBalance < _maxLoss) {
            revert TokenBalanceIsLessThanMaxLoss(tokenBalance, _maxLoss);
        }

        // Effects: Set initialization immutables
        marketCreator = marketCreator_;
        createdAt = block.timestamp;
        _marketMetadata = newMarketMetadata_;

        // Effects: Save new market
        _market = Market({
            config: newMarketConfig_,
            pool: tokenBalance, // Use tokenBalance here (not maxLoss) to account for possible surplus
            tradingFees: 0,
            expSum: newMarketConfig_.outcomeCount * 1e18,
            winningOutcomeIdx: type(uint256).max // Note: Sentinel value for "no winner yet"
        });
    }

    // ===== EXTERNAL FUNCTIONS =====

    /// @inheritdoc ILmsrMarket
    function buy(address buyer, uint256 outcomeIdx, uint256 tokensIn, uint256 sharesOut)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.OPEN)
        validOutcomeIdx(outcomeIdx)
    {
        // Deduct trading fee from tokens in
        (uint256 netTokensIn, uint256 feeAmount) = tokensIn.deductFee(_market.config.tradingFee);

        // Checks: Validate buy
        (uint256 newExpSum, bool valid) = _market.config.b
            .buyIsValid({
                currentExpSum: _market.expSum,
                outcomeCurrentSupply: totalSupply(outcomeIdx),
                tokensIn: netTokensIn,
                sharesOut: sharesOut,
                tokenDecimalScaler: TOKEN_DECIMAL_SCALER
            });
        if (!valid) {
            revert InvalidBuy();
        }

        // Effects: Update market
        _market.expSum = newExpSum;
        _market.pool += netTokensIn;
        _market.tradingFees += feeAmount;

        // Effects: Mint entry shares to buyer
        _mint(buyer, outcomeIdx, sharesOut);

        // Effects: Emit event
        emit Buy(buyer, outcomeIdx, tokensIn, sharesOut);

        // Interactions: Pull tokens from buyer
        TOKEN.safeTransferFrom(buyer, address(this), tokensIn);
    }

    /// @inheritdoc ILmsrMarket
    function sell(address seller, uint256 outcomeIdx, uint256 sharesIn, uint256 tokensOut)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.OPEN)
        validOutcomeIdx(outcomeIdx)
    {
        // Add trading fee to tokens out
        (uint256 grossTokensOut, uint256 feeAmount) = tokensOut.addFee(_market.config.tradingFee);

        // Checks: Ensure pool can cover gross tokens out (tokens out + fee)
        if (grossTokensOut > _market.pool) {
            revert GrossTokensOutExceedMarketPool(grossTokensOut, _market.pool);
        }

        // Checks: Validate sell
        (uint256 newExpSum, bool valid) = _market.config.b
            .sellIsValid({
                currentExpSum: _market.expSum,
                outcomeCurrentSupply: totalSupply(outcomeIdx),
                sharesIn: sharesIn,
                tokensOut: grossTokensOut,
                tokenDecimalScaler: TOKEN_DECIMAL_SCALER
            });
        if (!valid) {
            revert InvalidSell();
        }

        // Effects: Update market
        _market.expSum = newExpSum;
        _market.pool -= grossTokensOut;
        _market.tradingFees += feeAmount;

        // Effects: Burn entry shares from seller
        _burn(seller, outcomeIdx, sharesIn);

        // Effects: Emit event
        emit Sell(seller, outcomeIdx, sharesIn, tokensOut);

        // Interactions: Push tokens to seller
        TOKEN.safeTransfer(seller, tokensOut);
    }

    /// @inheritdoc ILmsrMarket
    /// @dev The oracle fee transfer is folded into this function (rather than a standalone
    ///      transferOracleFee) so it is intrinsically once-only: settleMarket can only run while
    ///      AWAITING_SETTLEMENT and sets the market to SETTLED, so a second call reverts before
    ///      any second oracle-fee transfer is possible. `oracleFeeRecipient` is a pass-through —
    ///      the market never stores or interprets it, preserving recipient-agnosticism.
    function settleMarket(uint256 winningOutcomeIdx, address oracleFeeRecipient)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.AWAITING_SETTLEMENT)
        validOutcomeIdx(winningOutcomeIdx)
        returns (uint256 losingPayout, uint256 tradingFeesRecipientTradingFeesCut, uint256 marketCreatorTradingFeesCut)
    {
        // Calculate winning payout
        uint256 winningPayout = totalSupply(winningOutcomeIdx) / TOKEN_DECIMAL_SCALER;

        // Calculate settlement reward
        losingPayout = _market.pool - winningPayout;

        // Calculate trading fees recipient cut
        tradingFeesRecipientTradingFeesCut =
            _market.tradingFees.tradingFeesRecipientCut({tradingFeesRecipientPct: TRADING_FEES_RECIPIENT_PCT});

        // Calculate market creator cut
        marketCreatorTradingFeesCut = _market.tradingFees - tradingFeesRecipientTradingFeesCut;

        // Effects: Update market
        _market.winningOutcomeIdx = winningOutcomeIdx;
        _market.pool = winningPayout;
        _market.tradingFees = 0;

        // Effects: Mark oracle fee as paid
        oracleFeePaid = true;

        // Effects: Emit event
        emit MarketSettled(
            winningOutcomeIdx, losingPayout, tradingFeesRecipientTradingFeesCut, marketCreatorTradingFeesCut
        );

        // Interactions: Give tradingFeesRecipientTradingFeesCut to TRADING_FEES_RECIPIENT
        // Note: TRADING_FEES_RECIPIENT is a Gensyn address, so blacklist risk is minimal.
        TOKEN.safeTransfer(TRADING_FEES_RECIPIENT, tradingFeesRecipientTradingFeesCut);

        // Calculate market creator reward
        uint256 marketCreatorSettlementReward = losingPayout + marketCreatorTradingFeesCut;

        // Interactions: Give losingPayout + marketCreatorTradingFeesCut to marketCreator
        bool success = TOKEN.trySafeTransfer(marketCreator, marketCreatorSettlementReward);
        if (success) {
            // Effects: Emit event
            emit MarketCreatorRewardTransferred(marketCreatorSettlementReward);
        } else {
            // Effects: Update market creator claimable
            marketCreatorClaimable += marketCreatorSettlementReward;
        }

        // Interactions: Transfer oracle fee to the recipient (e.g. oracle treasury). No-op when zero.
        if (ORACLE_FEE > 0) {
            // Note: oracleFeeRecipient is a trusted address, so blacklist risk is minimal.
            TOKEN.safeTransfer(oracleFeeRecipient, ORACLE_FEE);
        }
    }

    /// @inheritdoc ILmsrMarket
    function transferKeeperFee(address keeper)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.AWAITING_SETTLEMENT)
    {
        // Mark that resolution occurred and the keeper fee has left the proxy. Set unconditionally
        // (even when KEEPER_FEE == 0) so it reliably signals "resolveMarket happened"
        if (keeperFeePaid) {
            revert KeeperFeeAlreadyPaid();
        }
        // Checks: Resolution is gated until earliestResolveTime (TOB-GEN-LMSR-1 short-term mitigation) —
        // this is the sole choke point of the resolve flow, since the oracle only acts after resolveMarket.
        if (block.timestamp < _market.config.earliestResolveTime) {
            revert CannotResolveMarketYet(block.timestamp, _market.config.earliestResolveTime);
        }
        keeperFeePaid = true;
        if (KEEPER_FEE > 0) {
            // Note: Keeper will be the msg.sender. A blacklisted caller will only brick himself.
            TOKEN.safeTransfer(keeper, KEEPER_FEE);
        }
    }

    /// @inheritdoc ILmsrMarket
    /// @dev ifStatus(AWAITING_SETTLEMENT) means this reverts if the market has naturally expired
    ///      by the time the oracle callback arrives. In that case the relayer's delete on
    ///      pendingRequests is rolled back, leaving a stale entry. This is harmless on two
    ///      independent layers: (1) an honest WatchTower marks requests fulfilled before
    ///      calling back and will never replay; (2) even a malicious WatchTower cannot exploit
    ///      the stale entry — this guard ensures any replay attempt always reverts, making it
    ///      a guaranteed no-op.
    function failMarket() external nonReentrant onlyGateway ifStatus(MarketStatus.AWAITING_SETTLEMENT) {
        marketFailed = true;

        // Effects: Emit event
        emit MarketFailed();

        // Try to sweep any claimable rewards
        _trySweep(marketStatus());
    }

    /// @inheritdoc ILmsrMarket
    function redeem(address redeemer)
        external
        nonReentrant
        onlyGateway
        ifStatus(MarketStatus.SETTLED)
        returns (uint256 winningSharesIn, uint256 tokensOut)
    {
        // Get redeemer winning shares
        winningSharesIn = balanceOf(redeemer, _market.winningOutcomeIdx);

        /*
         * tokensOut > 0
         * winningSharesIn / TOKEN_DECIMAL_SCALER > 0
         * winningSharesIn >= TOKEN_DECIMAL_SCALER
         */
        if (winningSharesIn < TOKEN_DECIMAL_SCALER) {
            revert WinningSharesInAreLessThanTokenDecimalScaler(winningSharesIn, TOKEN_DECIMAL_SCALER);
        }

        // Calculate tokens out
        tokensOut = winningSharesIn.redeemerReward({tokenDecimalScaler: TOKEN_DECIMAL_SCALER});
        assert(tokensOut > 0);

        // Effects: Pull winning outcome shares from the redeemer
        _transfer({from: redeemer, to: address(this), id: _market.winningOutcomeIdx, amount: winningSharesIn});

        // Effects: Update market pool
        assert(tokensOut <= _market.pool); // Note: Key Invariant
        _market.pool -= tokensOut;

        // Effects: Emit event
        emit Redemption({redeemer: redeemer, winningSharesIn: winningSharesIn, tokensOut: tokensOut});

        // Interactions: Push tokens out
        TOKEN.safeTransfer(redeemer, tokensOut);
    }

    /// @inheritdoc ILmsrMarket
    function liquidate(address liquidator, uint256[] calldata outcomeIndices)
        external
        nonReentrant
        onlyGateway
        returns (uint256[] memory sharesIn, uint256 totalTokensOut)
    {
        // Checks: Only valid in EXPIRED or FAILED status
        MarketStatus _status = marketStatus();
        if (_status != MarketStatus.EXPIRED && _status != MarketStatus.FAILED) {
            revert MarketNotExpiredNorFailed(_status);
        }

        // Checks: Ensure outcomeIndices isn't empty
        if (outcomeIndices.length == 0) {
            revert OutcomeIndicesAreEmpty();
        }

        // Try to sweep any claimable rewards
        _trySweep(_status);

        // Effects: Initialize array lengths
        sharesIn = new uint256[](outcomeIndices.length);

        // Initialize sum var
        uint256 numeratorSum36 = 0;

        // For each outcome index
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            // Get outcome index
            uint256 outcomeIdx = outcomeIndices[i];

            // Checks: Validate outcome idx
            _validOutcomeIdx(outcomeIdx);

            // Get liquidator shares
            uint256 _sharesIn = balanceOf(liquidator, outcomeIdx);

            // Checks: Validate sharesIn
            if (_sharesIn == 0) {
                revert ZeroSharesIn();
            }

            // Update shares in array
            sharesIn[i] = _sharesIn;

            // Update sum var
            numeratorSum36 += _valueToAddToNumeratorSum36({sharesIn: _sharesIn, outcomeIdx: outcomeIdx});

            /* Effects: Pull outcome shares (don't burn them)
             * Burning would change the supplies, which would change the prices (even by a tiny amount).
             * Therefore, instead of burning, we just pull the shares into the market.
             * This will keep the prices the exact same, which will keep liquidations order-independent.
             */
            _transfer({from: liquidator, to: address(this), id: outcomeIdx, amount: _sharesIn});
        }

        // Calculate total tokens out
        totalTokensOut = numeratorSum36.liquidatorTotalReward({
            currentExpSum: _market.expSum, tokenDecimalScaler: TOKEN_DECIMAL_SCALER
        });
        if (totalTokensOut == 0) {
            revert TotalTokensOutIsZero(numeratorSum36, _market.expSum, TOKEN_DECIMAL_SCALER);
        }

        // Effects: Update market pool
        assert(totalTokensOut <= _market.pool); // Note: Key Invariant
        _market.pool -= totalTokensOut;

        // Effects: Emit event
        emit Liquidation({
            liquidator: liquidator, outcomeIndices: outcomeIndices, sharesIn: sharesIn, totalTokensOut: totalTokensOut
        });

        // Interactions: Push tokens out
        TOKEN.safeTransfer(liquidator, totalTokensOut);
    }

    /// @inheritdoc ILmsrMarket
    function trySweep() external nonReentrant onlyGateway {
        _trySweep(marketStatus());
    }

    /// @notice ERC-6909 transfer, with transfers to the market itself blocked (shares only enter the
    ///         market through redeem/liquidate, which account for them).
    /// @inheritdoc IERC6909
    function transfer(address receiver, uint256 id, uint256 amount)
        public
        virtual
        override(ERC6909, IERC6909)
        returns (bool)
    {
        if (receiver == address(this)) {
            revert CannotTransferSharesToMarket();
        }
        return super.transfer(receiver, id, amount);
    }

    /// @notice ERC-6909 transferFrom, with transfers to the market itself blocked (shares only enter the
    ///         market through redeem/liquidate, which account for them).
    /// @inheritdoc IERC6909
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount)
        public
        virtual
        override(ERC6909, IERC6909)
        returns (bool)
    {
        if (receiver == address(this)) {
            revert CannotTransferSharesToMarket();
        }
        return super.transferFrom(sender, receiver, id, amount);
    }

    // ===== EXTERNAL VIEW FUNCTIONS =====

    /// @inheritdoc IDelphiMarket
    function getMarketMetadata() external view returns (VerifiableUri memory) {
        return _marketMetadata;
    }

    /// @inheritdoc ILmsrMarket
    function getMarket() external view returns (Market memory) {
        return _market;
    }

    /// @inheritdoc ILmsrMarket
    function isValidOutcomeIdx(uint256 outcomeIdx) external view returns (bool) {
        return outcomeIdx < _market.config.outcomeCount;
    }

    /// @inheritdoc ILmsrMarket
    function marketStatus() public view returns (MarketStatus) {
        if (marketFailed) {
            return MarketStatus.FAILED;
        }

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

    /// @inheritdoc ILmsrMarket
    function totalSupplies(uint256[] calldata outcomeIndices) external view returns (uint256[] memory supplies) {
        supplies = new uint256[](outcomeIndices.length);
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            supplies[i] = totalSupply(outcomeIndices[i]);
        }
    }

    /// @inheritdoc ILmsrMarket
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

    /// @inheritdoc ILmsrMarket
    function spotPrice(uint256 outcomeIdx) public view validOutcomeIdx(outcomeIdx) returns (uint256) {
        if (marketStatus() == MarketStatus.SETTLED) {
            return outcomeIdx == _market.winningOutcomeIdx ? (1e18 / TOKEN_DECIMAL_SCALER) : 0;
        } else {
            return _market.config.b
                .spotPrice({
                    outcomeSupply: totalSupply(outcomeIdx),
                    marketExp: _market.expSum,
                    tokenDecimalScaler: TOKEN_DECIMAL_SCALER
                });
        }
    }

    /// @inheritdoc ILmsrMarket
    // Note: Do not use the math library directly (or the validOutcomeIdx check will be bypassed)
    function spotPrices(uint256[] calldata outcomeIndices) external view returns (uint256[] memory prices) {
        prices = new uint256[](outcomeIndices.length);
        for (uint256 i = 0; i < outcomeIndices.length; i++) {
            prices[i] = spotPrice(outcomeIndices[i]);
        }
    }

    /// @inheritdoc ILmsrMarket
    function spotImpliedProbability(uint256 outcomeIdx) public view validOutcomeIdx(outcomeIdx) returns (uint256) {
        if (marketStatus() == MarketStatus.SETTLED) {
            return outcomeIdx == _market.winningOutcomeIdx ? 1e18 : 0;
        } else {
            return _market.config.b
                .spotImpliedProbability({outcomeSupply: totalSupply(outcomeIdx), marketExp: _market.expSum});
        }
    }

    /// @inheritdoc ILmsrMarket
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

    /// @notice The maximum possible loss of a market with the given parameters: b * ln(outcomeCount).
    /// @param b The liquidity parameter (18 decimal fixed-point).
    /// @param outcomeCount The number of outcomes.
    /// @return The maximum loss, in token decimals (the minimum required initial deposit).
    function maxLoss(uint256 b, uint256 outcomeCount) public view returns (uint256) {
        return b.maxLoss(outcomeCount, TOKEN_DECIMAL_SCALER);
    }

    // ===== INTERNAL FUNCTIONS ====

    /// @dev Sweeps claimable rewards for EXPIRED/FAILED markets and retries any pending
    ///      market-creator transfer (relevant for SETTLED markets too, if the settlement-time
    ///      transfer failed, e.g. due to a token blacklist).
    /// @param marketStatus_ The market's current status (passed in to avoid recomputation).
    function _trySweep(MarketStatus marketStatus_) internal {
        // If market is EXPIRED or FAILED
        if (marketStatus_ == MarketStatus.EXPIRED || marketStatus_ == MarketStatus.FAILED) {
            _trySweepTradingFees();
            _trySweepLosingPayout();
            _trySweepKeeperFee();
            _trySweepOracleFee();
        }

        // If market creator has rewards to claim
        // Note: This is outside the if block above, as it could also be needed for SETTLED markets.
        if (marketCreatorClaimable > 0) {
            // Try to transfer market creator reward to market creator
            bool success = TOKEN.trySafeTransfer(marketCreator, marketCreatorClaimable);

            // If transfer successful
            if (success) {
                // Effects: Emit event
                emit MarketCreatorRewardTransferred(marketCreatorClaimable);

                // Effects:Zero out market creator claimable
                marketCreatorClaimable = 0;
            }
        }
    }

    /* Note: This function attempts a regular ERC20 transfer to the TRADING_FEES_RECIPIENT.
     * And it is called in trySweep(), which is called during liquidate() and failMarket().
     * Therefore, if the TRADING_FEES_RECIPIENT gets blacklisted, this would break liquidate() and failMarket().
     * However, unlike the market creator, the TRADING_FEES_RECIPIENT is a gensyn controlled address (which is unlikely to get blacklisted).
     */
    function _trySweepTradingFees() internal {
        // Get trading fees
        uint256 tradingFees = _market.tradingFees;

        if (tradingFees > 0) {
            // Effects: Zero out trading fees
            _market.tradingFees = 0;

            // Calculate trading fees recipient cut
            uint256 tradingFeesRecipientTradingFeesCut =
                tradingFees.tradingFeesRecipientCut({tradingFeesRecipientPct: TRADING_FEES_RECIPIENT_PCT});

            // Calculate market creator cut
            uint256 marketCreatorTradingFeesCut = tradingFees - tradingFeesRecipientTradingFeesCut;

            // Sweep trading fees to trading fees recipient
            // Note: TRADING_FEES_RECIPIENT is a Gensyn address, so blacklist risk is minimal.
            TOKEN.safeTransfer(TRADING_FEES_RECIPIENT, tradingFeesRecipientTradingFeesCut);

            // Sweep trading fees to market creator
            marketCreatorClaimable += marketCreatorTradingFeesCut;

            emit TradingFeesSwept(tradingFeesRecipientTradingFeesCut, marketCreatorTradingFeesCut);
        }
    }

    /// @dev Once-only: reserves the liquidation payout for all external shares at frozen prices and
    ///      accrues the pool remainder (the losing payout) to the market creator's claimable balance.
    function _trySweepLosingPayout() internal {
        if (!losingPayoutSwept) {
            // Mark that the losing payout has been swept
            losingPayoutSwept = true;

            // Initialize numerator sum
            uint256 numeratorSum36;

            // For each outcome
            for (uint256 outcomeIdx = 0; outcomeIdx < _market.config.outcomeCount; outcomeIdx++) {
                // Get outcome supply
                uint256 outcomeTotalSupply = totalSupply(outcomeIdx);

                // Get outcome external supply
                uint256 outcomeExternalSupply = outcomeTotalSupply - balanceOf(address(this), outcomeIdx);

                // Add to numerator sum
                /* Note: Use external (not total) supply here
                 * This is because some liquidations might have already happened.
                 * Therefore, some shares have already been pulled into the market.
                 * Therefore, the only shares that can still come in are the external shares.
                 */
                numeratorSum36 += _valueToAddToNumeratorSum36({sharesIn: outcomeExternalSupply, outcomeIdx: outcomeIdx});
            }

            // Calculate total liquidation payout
            uint256 totalLiquidationPayout = numeratorSum36.liquidatorTotalReward({
                currentExpSum: _market.expSum, tokenDecimalScaler: TOKEN_DECIMAL_SCALER
            });

            // Calculate remaining payout
            assert(_market.pool >= totalLiquidationPayout); // Note: Key Invariant
            uint256 remainingPayout = _market.pool - totalLiquidationPayout;

            if (remainingPayout > 0) {
                // Effects: Remove remaining payout from market pool
                _market.pool -= remainingPayout;

                // Effects: Sweep remaining payout to market creator
                marketCreatorClaimable += remainingPayout;
            }

            // Effects: Emit event
            emit LosingPayoutSwept(remainingPayout);
        }
    }

    /// @dev Once-only: accrues the unpaid keeper fee (market expired/failed without resolution) to the
    ///      market creator's claimable balance.
    function _trySweepKeeperFee() internal {
        if (!keeperFeePaid) {
            keeperFeePaid = true;
            if (KEEPER_FEE > 0) {
                marketCreatorClaimable += KEEPER_FEE;
            }
            emit KeeperFeeSwept(KEEPER_FEE);
        }
    }

    /// @dev Once-only: accrues the unpaid oracle fee (market expired/failed without settlement) to the
    ///      market creator's claimable balance.
    function _trySweepOracleFee() internal {
        if (!oracleFeePaid) {
            oracleFeePaid = true;
            if (ORACLE_FEE > 0) {
                marketCreatorClaimable += ORACLE_FEE;
            }
            emit OracleFeeSwept(ORACLE_FEE);
        }
    }

    // ===== INTERNAL VIEW FUNCTIONS ====

    /// @dev Computes one outcome's contribution to the liquidation numerator: sharesIn * outcomeExp.
    /// @param sharesIn The shares being valued (18 decimals).
    /// @param outcomeIdx The outcome index.
    /// @return The contribution to the numerator sum (36 decimal fixed-point).
    function _valueToAddToNumeratorSum36(uint256 sharesIn, uint256 outcomeIdx) internal view returns (uint256) {
        // Get outcome total supply
        uint256 outcomeTotalSupply = totalSupply(outcomeIdx);

        // Calculate outcome exp
        // Note: Use total (not external) supply here (to not change the prices)
        uint256 outcomeExp = _market.config.b.outcomeExp(outcomeTotalSupply);

        // Return value to add to numerator sum
        return sharesIn * outcomeExp;
    }

    /// @dev Validates all fields of a MarketConfig struct against the allowed bounds.
    /// @param config The market configuration to validate.
    function _validateLmsrConfig(MarketConfig memory config) internal view {
        // Validate outcome count
        if (config.outcomeCount < MIN_OUTCOME_COUNT) {
            revert OutcomeCountIsTooLow(config.outcomeCount, MIN_OUTCOME_COUNT);
        }
        if (config.outcomeCount > MAX_OUTCOME_COUNT) {
            revert OutcomeCountIsTooHigh(config.outcomeCount, MAX_OUTCOME_COUNT);
        }

        // Validate b
        if (config.b < MIN_B) {
            revert BIsTooLow(config.b, MIN_B);
        }
        if (config.b > MAX_B) {
            revert BIsTooHigh(config.b, MAX_B);
        }

        // Validate trading fee
        if (config.tradingFee < MIN_TRADING_FEE) {
            revert TradingFeeIsTooLow(config.tradingFee, MIN_TRADING_FEE);
        }
        if (config.tradingFee > MAX_TRADING_FEE) {
            revert TradingFeeIsTooHigh(config.tradingFee, MAX_TRADING_FEE);
        }

        // Validate trading deadline
        if (config.tradingDeadline <= block.timestamp) {
            revert TradingDeadlineIsNotInTheFuture(config.tradingDeadline, block.timestamp);
        }

        // Calculate trading window
        uint256 tradingWindow = config.tradingDeadline - block.timestamp;

        // Validate trading window
        if (tradingWindow < MIN_TRADING_WINDOW) {
            revert TradingWindowIsTooShort(tradingWindow, MIN_TRADING_WINDOW);
        }
        if (tradingWindow > MAX_TRADING_WINDOW) {
            revert TradingWindowIsTooLong(tradingWindow, MAX_TRADING_WINDOW);
        }

        // Validate earliest resolve time
        if (config.earliestResolveTime <= config.tradingDeadline) {
            revert EarliestResolveTimeIsNotAfterTheTradingDeadline(config.earliestResolveTime, config.tradingDeadline);
        }

        // Calculate resolve delay
        uint256 resolveDelay = config.earliestResolveTime - config.tradingDeadline;

        // Validate resolve delay
        if (resolveDelay < MIN_RESOLVE_DELAY) {
            revert ResolveDelayIsTooLow(resolveDelay, MIN_RESOLVE_DELAY);
        }
        if (resolveDelay > MAX_RESOLVE_DELAY) {
            revert ResolveDelayIsTooHigh(resolveDelay, MAX_RESOLVE_DELAY);
        }

        // Validate settlement deadline
        if (config.settlementDeadline <= config.earliestResolveTime) {
            revert SettlementDeadlineIsNotAfterTheEarliestResolveTime(
                config.settlementDeadline, config.earliestResolveTime
            );
        }

        // Calculate settlement window
        uint256 settlementWindow = config.settlementDeadline - config.earliestResolveTime;

        // Validate settlement window
        if (settlementWindow < MIN_SETTLEMENT_WINDOW) {
            revert SettlementWindowIsTooShort(settlementWindow, MIN_SETTLEMENT_WINDOW);
        }
        if (settlementWindow > MAX_SETTLEMENT_WINDOW) {
            revert SettlementWindowIsTooLong(settlementWindow, MAX_SETTLEMENT_WINDOW);
        }
    }

    /// @dev Reverts if the caller is not the gateway.
    function _onlyGateway() internal view {
        if (msg.sender != GATEWAY) {
            revert CallerIsNotGateway(msg.sender);
        }
    }

    /// @dev Reverts if the outcome index is out of bounds for the market.
    /// @param outcomeIdx The outcome index to validate.
    function _validOutcomeIdx(uint256 outcomeIdx) internal view {
        if (outcomeIdx >= _market.config.outcomeCount) {
            revert OutcomeIsOutOfBounds(outcomeIdx, _market.config.outcomeCount);
        }
    }

    /// @dev Reverts if the market is not in the required status.
    /// @param requiredStatus The expected market status.
    function _ifStatus(MarketStatus requiredStatus) internal view {
        ILmsrMarket.MarketStatus _marketStatus = marketStatus();
        if (_marketStatus != requiredStatus) {
            revert WrongMarketStatus(_marketStatus, requiredStatus);
        }
    }

    // ===== INTERNAL PURE FUNCTIONS ====

    /// @dev Ensures that a VerifiableUri has no empty fields.
    /// @param verifiableUri The URI to validate.
    function _validateVerifiableUri(VerifiableUri calldata verifiableUri) internal pure {
        if (bytes(verifiableUri.uri).length == 0) {
            revert UriIsEmpty();
        }
        if (verifiableUri.uriContentHash == bytes32(0)) {
            revert UriContentHashIsZero();
        }
    }
}
