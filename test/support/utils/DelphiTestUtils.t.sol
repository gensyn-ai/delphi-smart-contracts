// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiDeployer} from "script/utils/deployer/DelphiDeployer.sol";
import {BaseTest} from "test/support/utils/BaseTest.t.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {ILmsrMarket, IDelphiMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Libraries
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";

contract DelphiTestUtils is DelphiDeployer, BaseTest {
    // Libraries
    using Math for uint256;
    using LmsrMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // Libraries
    using LmsrMath for uint256;
    using Math for uint256;
    using stdStorage for StdStorage;

    // Structs
    struct AssertionHelperInfo {
        uint256 price;
        uint256 tokenDecimals;
    }

    struct BuyWithPermitVars {
        AssertionHelperInfo info;
        address buyer;
        uint256 boundedMaxTokensIn;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // Constants
    uint256 public constant BASIS_POINT = 0.000_1e18; // 0.01%
    uint256 public constant TOLERANCE = 10 * BASIS_POINT;

    // Constants
    string constant TOKEN_NAME = "MockToken";
    string constant TOKEN_SYMBOL = "MOCK";
    string constant VERIFIABLE_URI = "uri";
    bytes32 constant VERIFIABLE_URI_CONTENT_HASH = keccak256(abi.encode(VERIFIABLE_URI));
    uint256 constant ONE_TRILLION = 1_000_000_000_000;

    // Immutables
    address immutable TRADING_FEES_RECIPIENT = makeAddr("TRADING_FEES_RECIPIENT");
    address immutable MARKET_CREATION_FEE_RECIPIENT = makeAddr("MARKET_CREATION_FEE_RECIPIENT");
    address immutable GATEWAY_OWNER = makeAddr("GATEWAY_OWNER");
    address immutable TOKEN_ADMIN = makeAddr("TOKEN_ADMIN");
    address immutable MARKET_CREATOR = makeAddr("MARKET_CREATOR");
    address immutable KEEPER = makeAddr("KEEPER");

    // Internal Functions
    function _buyWithPermit(
        uint256 buyerPk,
        ILmsrGateway marketGateway,
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn
    )
        internal
        returns (
            bool, /*success*/
            bytes4, /*errSelector*/
            uint256 /*tokensIn*/
        )
    {
        uint256 freeMemPtr = _getFreeMemPtr();

        BuyWithPermitVars memory vars;

        uint256 tokensIn;
        {
            // Get tokens in
            (bool success, bytes4 errSelector, uint256 _tokensIn) =
                _tryQuoteBuyExactOut(marketGateway, marketProxy, outcomeIdx, sharesOut);
            if (!success) {
                return (false, errSelector, 0);
            }
            tokensIn = _tokensIn;
        }

        vars.info = _buyAssertionHelper(marketProxy, sharesOut, tokensIn);
        _assertPriceLessThanOne(vars.info);
        _assertPriceGreaterThanSpot(vars.info, marketProxy.spotPrice(outcomeIdx));

        vars.buyer = vm.addr(buyerPk);

        {
            // Get buyer tokens
            uint256 buyerTokens = marketGateway.TOKEN().balanceOf(vars.buyer);

            // If buyer has insufficient tokens, deal
            if (buyerTokens < tokensIn) {
                deal(address(marketGateway.TOKEN()), vars.buyer, tokensIn);
            }
        }

        // Switch to buyer
        _useNewSender(vars.buyer);

        vars.deadline = block.timestamp;
        vars.boundedMaxTokensIn = bound(maxTokensIn, tokensIn, type(uint256).max);
        (vars.v, vars.r, vars.s) = _signPermit({
            marketProxy: marketProxy,
            buyerPk: buyerPk,
            boundedMaxTokensIn: vars.boundedMaxTokensIn,
            deadline: vars.deadline
        });

        marketGateway.buyExactOutWithPermit({
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut,
            maxTokensIn: vars.boundedMaxTokensIn,
            deadline: vars.deadline,
            v: vars.v,
            r: vars.r,
            s: vars.s
        });

        _assertPriceLessThanSpot(vars.info, marketProxy.spotPrice(outcomeIdx));

        // Move free memory pointer back (to free everything in this function from memory)
        _setFreeMemPtr(freeMemPtr);

        return (true, 0, tokensIn);
    }

    function _buy(
        address buyer,
        ILmsrGateway marketGateway,
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn
    )
        internal
        returns (
            bool, /*success*/
            bytes4, /*errSelector*/
            uint256 /*tokensIn*/
        )
    {
        uint256 tokensIn;
        {
            // Get tokens in
            (bool success, bytes4 errSelector, uint256 _tokensIn) =
                _tryQuoteBuyExactOut(marketGateway, marketProxy, outcomeIdx, sharesOut);
            if (!success) {
                return (false, errSelector, 0);
            }
            tokensIn = _tokensIn;
        }

        AssertionHelperInfo memory info = _buyAssertionHelper(marketProxy, sharesOut, tokensIn);
        _assertPriceLessThanOne(info);
        _assertPriceGreaterThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        {
            // Get buyer tokens
            uint256 buyerTokens = marketGateway.TOKEN().balanceOf(buyer);

            // If buyer has insufficient tokens, deal
            if (buyerTokens < tokensIn) {
                deal(address(marketGateway.TOKEN()), buyer, tokensIn);
            }
        }

        // Approve tokens in
        _useNewSender(buyer);
        marketGateway.TOKEN().approve(address(marketProxy), tokensIn);

        // Buy
        marketGateway.buyExactOut({
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut,
            maxTokensIn: bound(maxTokensIn, tokensIn, type(uint256).max)
        });

        _assertPriceLessThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        return (true, 0, tokensIn);
    }

    function _sell(
        address seller,
        ILmsrGateway marketGateway,
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesIn,
        uint256 minTokensOut
    )
        internal
        returns (
            bool, /*success*/
            bytes4, /*errSelector*/
            uint256 /*tokensOut*/
        )
    {
        uint256 tokensOut;
        {
            (bool success, bytes4 errSelector, uint256 _tokensOut) =
                _tryQuoteSellExactIn(marketGateway, marketProxy, outcomeIdx, sharesIn);
            if (!success) {
                return (false, errSelector, 0);
            }
            tokensOut = _tokensOut;
        }

        AssertionHelperInfo memory info = _sellAssertionHelper(marketProxy, sharesIn, tokensOut);
        _assertPriceLessThanOne(info);
        _assertPriceLessThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        // Switch to seller
        _useNewSender(seller);

        // Sell Exact In
        marketGateway.sellExactIn({
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesIn: sharesIn,
            minTokensOut: bound(minTokensOut, 1, tokensOut)
        });

        _assertPriceGreaterThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        return (true, 0, tokensOut);
    }

    // Internal Functions
    function _deployBoundedTokenAndDelphiAndMarket(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    )
        internal
        returns (
            MockToken token,
            DelphiAddresses memory deployment,
            MockOracleRelayer oracleRelayer,
            ILmsrMarket marketProxy
        )
    {
        // Deploy Token
        token = _boundAndDeployToken(tokenDecimals);

        // Override delphi config token (so that token is used in delphi deployment)
        delphiConfig.token = token;

        // Deploy Delphi
        deployment = _boundAndDeployDelphi(delphiConfig);

        // Deploy oracle relayer
        oracleRelayer = new MockOracleRelayer(deployment.gateway);

        // Switch to gateway owner
        vm.prank(GATEWAY_OWNER);

        // Set oracle relayer
        deployment.gateway.setOracleRelayer(address(oracleRelayer));

        // Deploy Market
        marketProxy = _boundAndDeployMarket({
            marketConfig: marketConfig, deployment: deployment, token: token, initialDeposit: initialDeposit
        });
    }

    function _boundAndDeployToken(uint8 tokenDecimals) internal returns (MockToken token) {
        // Bound token decimals
        uint8 boundedTokenDecimals = _boundUint8(tokenDecimals, 6, 18);

        // Deploy Token
        token = new MockToken({
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            _decimals: boundedTokenDecimals,
            admin: TOKEN_ADMIN,
            initialAmount: 0
        });
    }

    function _boundAndDeployDelphi(DelphiConfig memory delphiConfig)
        internal
        returns (DelphiAddresses memory deployment)
    {
        // Bound delphi config
        DelphiConfig memory boundedDelphiConfig = _boundDelphiConfig(delphiConfig);

        // Deploy Delphi
        deployment = super._deployDelphi({args: boundedDelphiConfig});
    }

    function _boundAndDeployMarket(
        ILmsrMarket.MarketConfig memory marketConfig,
        DelphiAddresses memory deployment,
        IERC20Metadata token,
        uint256 initialDeposit
    ) internal returns (ILmsrMarket marketProxy) {
        // Bound market config
        ILmsrMarket.MarketConfig memory boundedMarketConfig =
            _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Calculate max loss
        uint256 maxLoss = boundedMarketConfig.b
            .maxLoss(boundedMarketConfig.outcomeCount, deployment.implementation.TOKEN_DECIMAL_SCALER());

        // Get market creation fee
        uint256 marketCreationFee = deployment.factory.MARKET_CREATION_FEE();

        // Bound initial deposit
        uint256 boundedInitialDeposit = bound(initialDeposit, maxLoss, _oneTrillionTokens(token) - marketCreationFee);

        // Deal initial deposit to market creator
        deal(address(token), MARKET_CREATOR, boundedInitialDeposit + marketCreationFee);

        // Switch to market creator
        _useNewSender(MARKET_CREATOR);

        // Approve factory to spend initial deposit
        token.approve(address(deployment.factory), boundedInitialDeposit + marketCreationFee);

        // Deploy new market proxy
        marketProxy = ILmsrMarket(
            deployment.factory
                .deployNewMarketProxy({
                    initialDeposit_: boundedInitialDeposit,
                    newMarketConfig_: boundedMarketConfig,
                    newMarketMetadata_: _dummyVerifiableUri()
                })
        );
    }

    /// @dev Quotes a buy of `sharesOut` shares, discarding the fuzz run when the trade is dust.
    ///      The gateway rejects buys whose token cost is below `MIN_TOKENS_DELTA` (a value floor that is
    ///      independent of, and stricter than, the `MIN_SHARES_DELTA` share floor most setup helpers bound on).
    ///      A dust buy is a legitimate rejection, not a test failure, so we drop the input via `vm.assume(false)`.
    function _quoteBuyOrSkip(ILmsrGateway gateway, ILmsrMarket marketProxy, uint256 outcomeIdx, uint256 sharesOut)
        internal
        view
        returns (uint256)
    {
        try gateway.quoteBuyExactOut({marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut}) returns (
            uint256 tokensIn, uint256, uint256
        ) {
            return tokensIn;
        } catch (bytes memory err) {
            if (_getErrorSelector(err) == ILmsrGatewayErrors.TokensInBelowMinTokensDelta.selector) {
                vm.assume(false);
            }
            _bubbleUpError(err);
        }
    }

    /// @dev Buys `sharesOut` of `outcomeIdx` for `buyer` through the gateway (market must be OPEN).
    ///      Leaves the active prank set to `buyer`.
    function _buyViaGateway(
        address buyer,
        ILmsrGateway gateway,
        ILmsrMarket marketProxy,
        IERC20 token,
        uint256 outcomeIdx,
        uint256 sharesOut
    ) internal returns (uint256 tokensIn) {
        tokensIn = _quoteBuyOrSkip(gateway, marketProxy, outcomeIdx, sharesOut);
        _useNewSender(buyer);
        deal(address(token), buyer, tokensIn);
        token.approve(address(marketProxy), tokensIn);
        gateway.buyExactOut({
            marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut, maxTokensIn: tokensIn
        });
    }

    /// @dev Directly sets `settlementLocked[proxy] = true` on the gateway (bypassing resolveMarket).
    function _lockSettlement(ILmsrGateway gateway, address marketProxy) internal {
        stdstore.target(address(gateway)).sig("settlementLocked(address)").with_key(marketProxy).checked_write(true);
    }

    // Internal Views
    function _getRandom(EnumerableSet.AddressSet storage set, uint256 idx) internal view returns (address) {
        return _getRandom(set.values(), idx);
    }

    function _getRandom(EnumerableSet.UintSet storage set, uint256 idx) internal view returns (uint256) {
        return _getRandom(set.values(), idx);
    }

    function _boundMarketConfig(ILmsrMarket implementation, ILmsrMarket.MarketConfig memory config)
        internal
        view
        returns (ILmsrMarket.MarketConfig memory)
    {
        // Get current time
        uint256 currentTime = block.timestamp;

        // Bound trading deadline
        uint256 tradingDeadline = bound(
            config.tradingDeadline,
            currentTime + implementation.MIN_TRADING_WINDOW(),
            currentTime + implementation.MAX_TRADING_WINDOW()
        );

        // Bound earliestResolveTime
        uint256 earliestResolveTime = bound(
            config.earliestResolveTime,
            tradingDeadline + implementation.MIN_RESOLVE_DELAY(),
            tradingDeadline + implementation.MAX_RESOLVE_DELAY()
        );

        // Bound b
        uint256 b = bound(config.b, implementation.MIN_B(), implementation.MAX_B());

        // Return random config
        return ILmsrMarketTypes.MarketConfig({
            outcomeCount: bound(
                config.outcomeCount, implementation.MIN_OUTCOME_COUNT(), implementation.MAX_OUTCOME_COUNT()
            ),
            b: b,
            tradingFee: bound(config.tradingFee, implementation.MIN_TRADING_FEE(), implementation.MAX_TRADING_FEE()),
            tradingDeadline: tradingDeadline,
            earliestResolveTime: earliestResolveTime,
            settlementDeadline: bound(
                config.settlementDeadline,
                earliestResolveTime + implementation.MIN_SETTLEMENT_WINDOW(),
                earliestResolveTime + implementation.MAX_SETTLEMENT_WINDOW()
            )
        });
    }

    function _tryQuoteBuyExactOut(
        ILmsrGateway marketGateway,
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut
    )
        internal
        view
        returns (
            bool, /* success */
            bytes4, /* errSelector */
            uint256 /* tokensOut */
        )
    {
        try marketGateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut) returns (
            uint256 tokensOut, uint256, uint256
        ) {
            return (true, 0, tokensOut);
        } catch (bytes memory err) {
            bytes4[] memory allowedBuyErrors = _quoteBuyExactOutAllowedErrors();
            bytes4 errSelector = _handleCatch(err, allowedBuyErrors);
            return (false, errSelector, 0);
        }
    }

    function _tryQuoteSellExactIn(
        ILmsrGateway marketGateway,
        ILmsrMarket marketProxy,
        uint256 outcomeIdx,
        uint256 sharesIn
    )
        internal
        view
        returns (
            bool, /* success */
            bytes4, /* errSelector */
            uint256 /* tokensOut */
        )
    {
        try marketGateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn) returns (
            uint256 tokensOut, uint256, uint256
        ) {
            return (true, 0, tokensOut);
        } catch (bytes memory err) {
            bytes4[] memory allowedSellErrors = _quoteSellExactInAllowedErrors();
            bytes4 errSelector = _handleCatch(err, allowedSellErrors);
            return (false, errSelector, 0);
        }
    }

    function _signPermit(ILmsrMarket marketProxy, uint256 buyerPk, uint256 boundedMaxTokensIn, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        IERC20Permit token = IERC20Permit(address(marketProxy.TOKEN()));
        address buyer = vm.addr(buyerPk);
        uint256 nonce = token.nonces(buyer);

        bytes32 permitStructHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                buyer,
                address(marketProxy),
                boundedMaxTokensIn,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), permitStructHash));
        (v, r, s) = vm.sign(buyerPk, digest);
    }

    // Internal Views
    function _boundDelphiConfig(DelphiConfig memory delphiConfig) internal view returns (DelphiConfig memory) {
        // Bound market creation fee
        uint256 boundedMarketCreationFee18 = bound(delphiConfig.marketCreationFee, 0, 100e18);
        uint256 boundedMarketCreationFee = boundedMarketCreationFee18 / 10 ** (18 - delphiConfig.token.decimals());

        // Bound keeper fee
        uint256 boundedKeeperFee = bound(delphiConfig.keeperFee, 0, boundedMarketCreationFee);

        // Bound oracle fee
        uint256 boundedOracleFee = bound(delphiConfig.oracleFee, 0, boundedMarketCreationFee - boundedKeeperFee);

        // Bound trading fees recipient pct
        uint256 boundedTradingFeesRecipientPct = bound(delphiConfig.tradingFeesRecipientPct, 0, 1e18);

        // Return bounded delphi config
        return DelphiConfig({
            tradingFeesRecipient: TRADING_FEES_RECIPIENT,
            marketCreationFeeRecipient: MARKET_CREATION_FEE_RECIPIENT,
            marketCreationFee: boundedMarketCreationFee,
            keeperFee: boundedKeeperFee,
            oracleFee: boundedOracleFee,
            tradingFeesRecipientPct: boundedTradingFeesRecipientPct,
            token: delphiConfig.token,
            gatewayOwner: GATEWAY_OWNER
        });
    }

    // expInput > MAX_EXP_INPUT
    // expInput >= MAX_EXP_INPUT + 1
    // outcomeSupply.mulDiv(1e18, b) >= MAX_EXP_INPUT + 1
    // (outcomeCurrentSupply + sharesOut).mulDiv(1e18, b) >= MAX_EXP_INPUT + 1
    // outcomeCurrentSupply + sharesOut >= (MAX_EXP_INPUT + 1).mulDiv(b, 1e18, Math.Rounding.Ceil)
    // sharesOut >= (MAX_EXP_INPUT + 1).mulDiv(b, 1e18, Math.Rounding.Ceil) - outcomeCurrentSupply
    function _minSharesOutForExpTooBig(ILmsrMarket marketProxy_, uint256 outcomeIdx) internal view returns (uint256) {
        return (LmsrMath.MAX_EXP_INPUT + 1).mulDiv(marketProxy_.getMarket().config.b, 1e18, Math.Rounding.Ceil)
            - marketProxy_.totalSupply(outcomeIdx);
    }

    /*
     * expInput <= MAX_EXP_INPUT
     * outcomeSupply.mulDiv(1e18, b) <= MAX_EXP_INPUT
     * (outcomeCurrentSupply + sharesOut).mulDiv(1e18, b) <= MAX_EXP_INPUT
     * outcomeCurrentSupply + sharesOut <= MAX_EXP_INPUT.mulDiv(b, 1e18)
     * sharesOut <= MAX_EXP_INPUT.mulDiv(b, 1e18) - outcomeCurrentSupply
     */
    function _maxSharesOut(ILmsrMarket marketProxy_, uint256 outcomeIdx) internal view returns (uint256) {
        ILmsrMarket.Market memory market = marketProxy_.getMarket();
        return LmsrMath.MAX_EXP_INPUT.mulDiv(market.config.b, 1e18) - marketProxy_.totalSupply(outcomeIdx);
    }

    /* netTokensIn >= 1
     * tokensIn.mulDiv(1e18 - tradingFee, 1e18, Math.Rounding.Floor) >= 1
     * tokensIn >= 1.mulDiv(1e18, 1e18 - tradingFee, Math.Rounding.Ceil)
     */
    function _minTokensIn(ILmsrMarket marketProxy_) internal view returns (uint256) {
        return uint256(1).mulDiv(1e18, 1e18 - marketProxy_.getMarket().config.tradingFee, Math.Rounding.Ceil);
    }

    function _oneTrillionTokens(IERC20Metadata token) internal view returns (uint256) {
        return ONE_TRILLION * (10 ** token.decimals());
    }

    /* outcomeNewSupply >= MIN_SHARES_DELTA
     * outcomeSupply - sharesIn >= MIN_SHARES_DELTA
     * - sharesIn >= MIN_SHARES_DELTA - outcomeSupply
     * sharesIn <= outcomeSupply - MIN_SHARES_DELTA
     */
    function maxSharesIn(ILmsrMarket marketProxy_, ILmsrGateway gateway, uint256 outcomeIdx)
        internal
        view
        returns (uint256)
    {
        return marketProxy_.totalSupply(outcomeIdx) - gateway.MIN_SHARES_DELTA();
    }

    /* grossTokensOut <= pool
     * tokensOut.mulDiv(1e18, 1e18 - tradingFee, Math.Rounding.Ceil) <= pool
     * tokensOut <= pool.mulDiv(1e18 - tradingFee, 1e18, Math.Rounding.Floor)
     */
    function _maxTokensOut(ILmsrMarket marketProxy_) internal view returns (uint256) {
        return marketProxy_.getMarket().pool
            .mulDiv(1e18 - marketProxy_.getMarket().config.tradingFee, 1e18, Math.Rounding.Floor);
    }

    // Internal Pure
    function _quoteBuyExactOutAllowedErrors() internal pure returns (bytes4[] memory errSelectors) {
        // Initialize error selectors
        errSelectors = new bytes4[](1);

        // Build error selectors
        errSelectors[0] = ILmsrGatewayErrors.TokensInBelowMinTokensDelta.selector;
    }

    function _quoteSellExactInAllowedErrors() internal pure returns (bytes4[] memory errSelectors) {
        // Initialize error selectors
        errSelectors = new bytes4[](4);

        // Build error selectors
        errSelectors[0] = ILmsrMathErrors.SellTooSmall.selector;
        errSelectors[1] = ILmsrMathErrors.RatioTooSmall.selector;
        errSelectors[2] = ILmsrMathErrors.LnInputTooSmall.selector;
        errSelectors[3] = ILmsrGatewayErrors.TokensOutBelowMinTokensDelta.selector;
    }

    function _liquidateAllowedErrors() internal pure returns (bytes4[] memory errSelectors) {
        // Initialize error selectors
        errSelectors = new bytes4[](1);

        // Build error selectors
        errSelectors[0] = ILmsrMarketErrors.TotalTokensOutIsZero.selector;
    }

    function _adjustUp(uint256 value, uint256 adjustment) internal pure returns (uint256) {
        return value.mulDiv(ONE + adjustment, ONE, Math.Rounding.Ceil);
    }

    function _adjustDown(uint256 value, uint256 adjustment) internal pure returns (uint256) {
        require(adjustment <= ONE, "_adjustDown underflow");
        return value.mulDiv(ONE - adjustment, ONE, Math.Rounding.Floor);
    }

    function _getRandom(address[] memory array, uint256 seed) internal pure returns (address randomElement) {
        randomElement = array[_getRandomIdx(array.length, seed)];
    }

    function _getRandom(uint256[] memory array, uint256 seed) internal pure returns (uint256 randomElement) {
        randomElement = array[_getRandomIdx(array.length, seed)];
    }

    function _getRandomIdx(uint256 length, uint256 seed) internal pure returns (uint256 randomIdx) {
        require(length > 0, "_getRandomIdx: length cannot be zero");
        randomIdx = bound(seed, 0, length - 1);
    }

    // Internal Pure
    function _dummyVerifiableUri() internal pure returns (ILmsrMarket.VerifiableUri memory) {
        return IDelphiMarket.VerifiableUri({uri: VERIFIABLE_URI, uriContentHash: VERIFIABLE_URI_CONTENT_HASH});
    }

    // Private Views
    function _buyAssertionHelper(ILmsrMarket marketProxy, uint256 sharesOut, uint256 tokensIn)
        private
        view
        returns (AssertionHelperInfo memory)
    {
        // Get market config
        ILmsrMarket.MarketConfig memory config = marketProxy.getMarket().config;

        // Get token decimals
        uint256 tokenDecimals = marketProxy.TOKEN().decimals();

        // Get net tokens in
        (uint256 netTokensIn,) = tokensIn.deductFee(config.tradingFee);

        // Calculate trade price
        uint256 price = netTokensIn.mulDiv(ONE, sharesOut);

        return AssertionHelperInfo({price: price, tokenDecimals: tokenDecimals});
    }

    function _sellAssertionHelper(ILmsrMarket marketProxy, uint256 sharesIn, uint256 tokensOut)
        private
        view
        returns (AssertionHelperInfo memory)
    {
        // Get market config
        ILmsrMarket.MarketConfig memory config = marketProxy.getMarket().config;

        // Get token decimals
        uint256 tokenDecimals = marketProxy.TOKEN().decimals();

        // Get gross tokens out
        (uint256 grossTokensOut,) = tokensOut.addFee(config.tradingFee);

        // Calculate trade price
        uint256 price = grossTokensOut.mulDiv(ONE, sharesIn);

        return AssertionHelperInfo({
            // b: _adjustUp(config.b / marketProxy.TOKEN_DECIMAL_SCALER(), BASIS_POINT),
            price: price,
            tokenDecimals: tokenDecimals
        });
    }

    // Private Pure
    function _assertPriceLessThanOne(AssertionHelperInfo memory info) private pure {
        uint256 one = 10 ** info.tokenDecimals;
        assertLtDecimal(info.price, _adjustUp(one, TOLERANCE), info.tokenDecimals, "Buy | Actual price bigger than one");
    }

    function _assertPriceGreaterThanSpot(AssertionHelperInfo memory info, uint256 spotPrice) private pure {
        assertGeDecimal(
            info.price,
            _adjustDown(spotPrice, TOLERANCE),
            info.tokenDecimals,
            "trade actual price not > adjusted spotPrice"
        );
    }

    function _assertPriceLessThanSpot(AssertionHelperInfo memory info, uint256 spotPrice) private pure {
        assertLeDecimal(
            info.price,
            _adjustUp(spotPrice, TOLERANCE),
            info.tokenDecimals,
            "trade actual price not < adjusted spotPrice"
        );
    }

    // EVM mem utils
    function _getFreeMemPtr() private pure returns (uint256 ptr) {
        assembly ("memory-safe") {
            ptr := mload(0x40)
        }
    }

    function _setFreeMemPtr(uint256 ptr) private pure {
        assembly ("memory-safe") {
            mstore(0x40, ptr)
        }
    }
}
