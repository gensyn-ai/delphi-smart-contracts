// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseTest} from "test/utils/BaseTest.t.sol";

// Interfaces
import {IDynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGateway.sol";
import {
    IDynamicParimutuelGatewayErrors
} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGatewayErrors.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";
import {
    IDynamicParimutuelMarketErrors
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketErrors.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IEndToEndHandler} from "../invariant/handlers/IEndToEndHandler.sol";
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";

// Libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DynamicParimutuelMath} from "src/delphi/dynamicParimutuel/math/DynamicParimutuelMath.sol";
import {LmsrMath} from "src/delphi/dynamicParimutuel/math/LmsrMath.sol";

import {console} from "forge-std/console.sol";

contract DelphiTestUtils is BaseTest {
    // Libraries
    using SafeCast for uint256;
    using Math for uint256;
    using DynamicParimutuelMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using LmsrMath for uint256;

    // Constants
    uint256 public constant BASIS_POINT = 0.000_1e18; // 0.01%

    function _getRandom(EnumerableSet.AddressSet storage set, uint256 idx) internal view returns (address) {
        return _getRandom(set.values(), idx);
    }

    function _getRandom(EnumerableSet.UintSet storage set, uint256 idx) internal view returns (uint256) {
        return _getRandom(set.values(), idx);
    }

    function _getRandom(address[] memory array, uint256 idx) private pure returns (address randomElement) {
        // Validate array length
        require(array.length > 0, "_getRandom: array length is zero");

        // Get random index
        uint256 randomIdx = bound(idx, 0, array.length - 1);

        // Get random element
        randomElement = array[randomIdx];
    }

    function _getRandom(uint256[] memory array, uint256 idx) private pure returns (uint256 randomElement) {
        // Validate array length
        require(array.length > 0, "_getRandom: array length is zero");

        // Get random index
        uint256 randomIdx = bound(idx, 0, array.length - 1);

        // Get random element
        randomElement = array[randomIdx];
    }

    // b = (initialLiquidity_ * TOKEN_DECIMAL_SCALER * 1e18) / (newMarketConfig_.outcomeCount * 1e18)._computeLnLowerBound();
    //
    // (initialLiquidity_ * TOKEN_DECIMAL_SCALER * 1e18) / (newMarketConfig_.outcomeCount * 1e18)._computeLnLowerBound() >= MIN_B
    // initialLiquidity_ >= (MIN_B * (newMarketConfig_.outcomeCount * 1e18)._computeLnLowerBound()) / (TOKEN_DECIMAL_SCALER * 1e18)
    //
    // (initialLiquidity_ * TOKEN_DECIMAL_SCALER * 1e18) / (newMarketConfig_.outcomeCount * 1e18)._computeLnLowerBound() <= MAX_B
    // initialLiquidity <= (MAX_B * (newMarketConfig_.outcomeCount * 1e18)._computeLnLowerBound()) / (TOKEN_DECIMAL_SCALER * 1e18)
    function _boundDeployMarketArgs(
        IDynamicParimutuelMarket implementation,
        IEndToEndHandler.DeployMarketArgs memory args
    ) internal view returns (IEndToEndHandler.DeployMarketArgs memory) {
        // Bound MarketConfig
        IDynamicParimutuelMarket.MarketConfig memory newMarketConfig =
            _boundMarketConfig({implementation: implementation, config: args.newMarketConfig});

        uint minInitialLiquidity1 = implementation.MIN_INITIAL_LIQUIDITY();
        uint minInitialLiquidity2 = (implementation.MIN_B() * (newMarketConfig.outcomeCount * 1e18)._computeLnLowerBound()) / (implementation.TOKEN_DECIMAL_SCALER() * 1e18);
        uint minInitialLiquidity = minInitialLiquidity1 > minInitialLiquidity2 ? minInitialLiquidity1 : minInitialLiquidity2;
        // console.log("minInitialLiquidity", minInitialLiquidity);

        uint maxInitialLiquidity1 = implementation.MAX_INITIAL_LIQUIDITY();
        uint maxInitialLiquidity2 = (implementation.MAX_B() * (newMarketConfig.outcomeCount * 1e18)._computeLnLowerBound()) / (implementation.TOKEN_DECIMAL_SCALER() * 1e18);
        uint maxInitialLiquidity = maxInitialLiquidity1 < maxInitialLiquidity2 ? maxInitialLiquidity1 : maxInitialLiquidity2;
        // console.log("maxInitialLiquidity", maxInitialLiquidity);

        // Return DeployMarkeArgs
        return IEndToEndHandler.DeployMarketArgs({
            newMarketMetadata: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
            marketCreator: args.marketCreator,
            newMarketConfig: newMarketConfig,
            initialLiquidity: bound(
                args.initialLiquidity, minInitialLiquidity, maxInitialLiquidity
            ),
            winningOutcomeIdx: bound(args.winningOutcomeIdx, 0, newMarketConfig.outcomeCount - 1)
        });
    }

    function _boundMarketConfig(
        IDynamicParimutuelMarket implementation,
        IDynamicParimutuelMarket.MarketConfig memory config
    ) internal view returns (IDynamicParimutuelMarket.MarketConfig memory) {
        // Get current time
        uint256 currentTime = block.timestamp;

        // Bound trading deadline
        uint256 tradingDeadline = bound(
            config.tradingDeadline,
            currentTime + implementation.MIN_TRADING_WINDOW(),
            currentTime + implementation.MAX_TRADING_WINDOW()
        );

        // Bound b
        // uint256 b = bound(config.b, implementation.MIN_B(), implementation.MAX_B());

        // Return random config
        return IDynamicParimutuelMarketTypes.MarketConfig({
            outcomeCount: bound(
                config.outcomeCount, implementation.MIN_OUTCOME_COUNT(), implementation.MAX_OUTCOME_COUNT()
            ),
            // b: b,
            // tradingFee: bound(config.tradingFee, implementation.MIN_TRADING_FEE(), implementation.MAX_TRADING_FEE()),
            tradingFee: 0,
            tradingDeadline: tradingDeadline,
            settlementDeadline: bound(
                config.settlementDeadline,
                tradingDeadline + implementation.MIN_SETTLEMENT_WINDOW(),
                tradingDeadline + implementation.MAX_SETTLEMENT_WINDOW()
            )
        });
    }

    function _quoteBuyExactOut(
        IDynamicParimutuelGateway marketGateway,
        IDynamicParimutuelMarket marketProxy,
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
        try marketGateway.quoteBuyExactOut(marketProxy, outcomeIdx, sharesOut) returns (uint256 tokensOut) {
            return (true, 0, tokensOut);
        } catch (bytes memory err) {
            bytes4[] memory allowedBuyErrors = _quoteBuyExactOutAllowedErrors();
            bytes4 errSelector = _handleCatch(err, allowedBuyErrors);
            return (false, errSelector, 0);
        }
    }

    function _quoteSellExactIn(
        IDynamicParimutuelGateway marketGateway,
        IDynamicParimutuelMarket marketProxy,
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
        try marketGateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn) returns (uint256 tokensOut) {
            return (true, 0, tokensOut);
        } catch (bytes memory err) {
            bytes4[] memory allowedSellErrors = _quoteSellExactInAllowedErrors();
            bytes4 errSelector = _handleCatch(err, allowedSellErrors);
            return (false, errSelector, 0);
        }
    }

    struct AssertionHelperInfo {
        uint256 b;
        uint256 price;
        uint256 tokenDecimals;
    }

    // function _buyAssertionHelper(IDynamicParimutuelMarket marketProxy, uint256 sharesOut, uint256 tokensIn)
    //     private
    //     view
    //     returns (AssertionHelperInfo memory)
    // {
    //     // Get market config
    //     IDynamicParimutuelMarket.MarketConfig memory config = marketProxy.getMarket().config;

    //     // Get token decimals
    //     uint256 tokenDecimals = marketProxy.TOKEN().decimals();

    //     // Get net tokens in
    //     (uint256 netTokensIn,) = tokensIn.deductFee(config.tradingFee);

    //     // Calculate trade price
    //     uint256 price = netTokensIn.mulDiv(ONE, sharesOut);

    //     return AssertionHelperInfo({
    //         b: _adjustUp(config.b / marketProxy.TOKEN_DECIMAL_SCALER(), BASIS_POINT),
    //         price: price,
    //         tokenDecimals: tokenDecimals
    //     });
    // }

    // function _sellAssertionHelper(IDynamicParimutuelMarket marketProxy, uint256 sharesIn, uint256 tokensOut)
    //     private
    //     view
    //     returns (AssertionHelperInfo memory)
    // {
    //     // Get market config
    //     IDynamicParimutuelMarket.MarketConfig memory config = marketProxy.getMarket().config;

    //     // Get token decimals
    //     uint256 tokenDecimals = marketProxy.TOKEN().decimals();

    //     // Get gross tokens out
    //     (uint256 grossTokensOut,) = tokensOut.addFee(config.tradingFee);

    //     // Calculate trade price
    //     uint256 price = grossTokensOut.mulDiv(ONE, sharesIn);

    //     return AssertionHelperInfo({
    //         b: _adjustUp(config.b / marketProxy.TOKEN_DECIMAL_SCALER(), BASIS_POINT),
    //         price: price,
    //         tokenDecimals: tokenDecimals
    //     });
    // }

    function _assertPriceLessThanK(AssertionHelperInfo memory info) private pure {
        assertLtDecimal(info.price, info.b, info.tokenDecimals, "Buy | Actual price bigger than k");
    }

    function _assertPriceGreaterThanSpot(AssertionHelperInfo memory info, uint256 spotPrice) private pure {
        assertGtDecimal(
            info.price,
            _adjustDown(spotPrice, 10 * BASIS_POINT),
            info.tokenDecimals,
            "trade actual price not > adjusted spotPrice"
        );
    }

    function _assertPriceLessThanSpot(AssertionHelperInfo memory info, uint256 spotPrice) private pure {
        assertLtDecimal(
            info.price,
            _adjustUp(spotPrice, 10 * BASIS_POINT),
            info.tokenDecimals,
            "trade actual price not < adjusted spotPrice"
        );
    }

    function _buy(
        address buyer,
        IDynamicParimutuelGateway marketGateway,
        IDynamicParimutuelMarket marketProxy,
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
                _quoteBuyExactOut(marketGateway, marketProxy, outcomeIdx, sharesOut);
            if (!success) {
                return (false, errSelector, 0);
            }
            tokensIn = _tokensIn;
        }

        // AssertionHelperInfo memory info = _buyAssertionHelper(marketProxy, sharesOut, tokensIn);
        // _assertPriceLessThanK(info);
        // _assertPriceGreaterThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        IERC20Metadata gensynTokenProxy = marketGateway.TOKEN();

        // Get buyer tokens
        uint256 buyerTokens = gensynTokenProxy.balanceOf(buyer);

        // If buyer has insufficient tokens, deal
        if (buyerTokens < tokensIn) {
            deal(address(gensynTokenProxy), buyer, tokensIn);
        }

        // Switch to buyer
        _useNewSender(buyer);

        // Approve tokens in
        gensynTokenProxy.approve(address(marketProxy), tokensIn);

        // Buy
        marketGateway.buyExactOut({
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut,
            maxTokensIn: bound(maxTokensIn, tokensIn, type(uint256).max)
        });

        // _assertPriceLessThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        return (true, 0, tokensIn);
    }

    function _sell(
        address seller,
        IDynamicParimutuelGateway marketGateway,
        IDynamicParimutuelMarket marketProxy,
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
                _quoteSellExactIn(marketGateway, marketProxy, outcomeIdx, sharesIn);
            if (!success) {
                return (false, errSelector, 0);
            }
            tokensOut = _tokensOut;
        }

        // AssertionHelperInfo memory info = _sellAssertionHelper(marketProxy, sharesIn, tokensOut);
        // _assertPriceLessThanK(info);
        // _assertPriceLessThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        // Switch to seller
        _useNewSender(seller);

        // Sell Exact In
        marketGateway.sellExactIn({
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesIn: sharesIn,
            minTokensOut: bound(minTokensOut, 1, tokensOut)
        });

        // _assertPriceGreaterThanSpot(info, marketProxy.spotPrice(outcomeIdx));

        return (true, 0, tokensOut);
    }

    function _quoteBuyExactOutAllowedErrors() internal pure returns (bytes4[] memory errSelectors) {
        // Initialize error selectors
        errSelectors = new bytes4[](2);

        // Build error selectors
        errSelectors[0] = IDynamicParimutuelGatewayErrors.TokensInBelowMin.selector;
        errSelectors[1] = IDynamicParimutuelGatewayErrors.OutcomeNewExpInputTooLarge.selector;
    }

    function _quoteSellExactInAllowedErrors() internal pure returns (bytes4[] memory errSelectors) {
        // Initialize error selectors
        errSelectors = new bytes4[](3);

        // Build error selectors
        errSelectors[0] = IDynamicParimutuelGatewayErrors.SellOverlap.selector;
        errSelectors[1] = IDynamicParimutuelGatewayErrors.GrossTokensOutNotPositive.selector;
        errSelectors[2] = IDynamicParimutuelGatewayErrors.TokensOutBelowMin.selector;
    }

    function _redeemAllowedErrors() internal pure returns (bytes4[] memory errSelectors) {
        // Initialize error selectors
        errSelectors = new bytes4[](1);

        // Build error selectors
        errSelectors[0] = IDynamicParimutuelMarketErrors.RedeemZeroTokensOut.selector;
    }

    function _adjustUp(uint256 value, uint256 adjustment) internal pure returns (uint256) {
        return value.mulDiv(ONE + adjustment, ONE);
    }

    function _adjustDown(uint256 value, uint256 adjustment) internal pure returns (uint256) {
        require(adjustment <= ONE, "_adjustDown underflow");
        return value.mulDiv(ONE - adjustment, ONE);
    }
}
