// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract LmsrMarket_Sell_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Tests
    function testFuzz_Sell_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensOut,
        uint256 sharesIn,
        address caller,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Switch to caller
        _useNewSender(caller);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.CallerIsNotGateway.selector, caller));

        // Buy
        marketProxy.sell({seller: user, outcomeIdx: outcomeIdx, tokensOut: tokensOut, sharesIn: sharesIn});
    }

    function testFuzz_Sell_MarketNotOpen_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensOut,
        uint256 sharesIn,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Advance time past trading deadline
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.WrongMarketStatus.selector,
                ILmsrMarketTypes.MarketStatus.AWAITING_SETTLEMENT,
                ILmsrMarketTypes.MarketStatus.OPEN
            )
        );

        // Buy
        marketProxy.sell({seller: user, outcomeIdx: outcomeIdx, tokensOut: tokensOut, sharesIn: sharesIn});
    }

    function testFuzz_Sell_GrossTokensOutExceedMarketPool_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 sharesIn,
        uint256 tokensOut,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Quote buy
        uint256 requiredTokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        // Bound tokens in
        tokensIn = bound(tokensIn, requiredTokensIn, 1_000_000_000_000 * (10 ** token.decimals()));

        // Ensure user isn't zero address
        vm.assume(user != address(0));

        // Switch to user
        _useNewSender(user);

        // Deal tokens in to user
        deal(address(token), user, tokensIn);

        // Approve tokens in to market proxy
        token.approve(address(marketProxy), tokensIn);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Buy
        marketProxy.buy({buyer: user, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Bound shares in
        sharesIn = bound(sharesIn, deployment.gateway.MIN_SHARES_DELTA(), marketProxy.totalSupply(outcomeIdx));

        if (_maxTokensOut({marketProxy_: marketProxy}) + 1 > _oneTrillionTokens(token)) {
            tokensOut = _maxTokensOut({marketProxy_: marketProxy}) + 1;
        } else {
            tokensOut = bound(tokensOut, _maxTokensOut({marketProxy_: marketProxy}) + 1, _oneTrillionTokens(token));
        }

        // Calculate gross tokens out
        (uint256 grossTokensOut,) = tokensOut.addFee(marketProxy.getMarket().config.tradingFee);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.GrossTokensOutExceedMarketPool.selector, grossTokensOut, marketProxy.getMarket().pool
            )
        );

        // Sell
        marketProxy.sell({seller: user, outcomeIdx: outcomeIdx, tokensOut: tokensOut, sharesIn: 0});
    }

    // Note: No tests for sqrt overlap or sell too small

    function testFuzz_Sell_InvalidSell_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 tokensOut,
        uint256 sharesIn,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Quote buy
        uint256 requiredTokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        // Bound tokens in
        tokensIn = bound(tokensIn, requiredTokensIn, 1_000_000_000_000 * (10 ** token.decimals()));

        // Ensure user isn't zero address
        vm.assume(user != address(0));

        // Switch to user
        _useNewSender(user);

        // Deal tokens in to user
        deal(address(token), user, tokensIn);

        // Approve tokens in to market proxy
        token.approve(address(marketProxy), tokensIn);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Buy
        marketProxy.buy({buyer: user, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Bound shares in
        sharesIn = bound(sharesIn, deployment.gateway.MIN_SHARES_DELTA(), sharesOut);

        // Get max shares in
        uint256 maxSharesIn = maxSharesIn(marketProxy, deployment.gateway, outcomeIdx);

        // If 0 < new outcome supply < MIN_SHARES_DELTA
        if (sharesIn != sharesOut && sharesIn > maxSharesIn) {
            // Re-bound shares in
            if (deployment.gateway.MIN_SHARES_DELTA() > maxSharesIn) {
                sharesIn = marketProxy.totalSupply(outcomeIdx);
            } else {
                sharesIn = bound(sharesIn, deployment.gateway.MIN_SHARES_DELTA(), maxSharesIn);
            }
        }

        // Try to quote sell exact in
        try deployment.gateway
        .quoteSellExactIn({marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesIn}) returns (
            uint256 expectedTokensOut, uint256, uint256
        ) {
            // Keep tokens out above expected tokens out
            tokensOut = bound(tokensOut, expectedTokensOut + 1, _maxTokensOut({marketProxy_: marketProxy}));

            // Expect Revert
            vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.InvalidSell.selector));

            // Buy
            marketProxy.sell({seller: user, outcomeIdx: outcomeIdx, tokensOut: tokensOut, sharesIn: sharesIn});

            // Catch error
        } catch (bytes memory err) {
            // Ensure error is expected
            _handleCatch(err, _quoteSellExactInAllowedErrors());
        }
    }

    // Note: To solve stack depth issues
    struct SellArgs {
        uint256 outcomeIdx;
        uint256 sharesOut;
        uint256 tokensOut;
        uint256 sharesIn;
        address user;
    }

    // Note: To solve stack depth issues
    struct SellExpectations {
        uint256 marketExpSum;
        uint256 marketPool;
        uint256 marketTradingFees;
        uint256 outcomeSupply;
        uint256 outcomeBalance;
        uint256 userTokens;
        uint256 marketTokens;
    }

    function testFuzz_Sell_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        SellArgs memory args
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx
        args.outcomeIdx = bound(args.outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        args.sharesOut = bound(
            args.sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: args.outcomeIdx})
        );

        // Quote buy
        uint256 requiredTokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, args.outcomeIdx, args.sharesOut);

        // Bound tokens in
        args.tokensOut = bound(args.tokensOut, requiredTokensIn, _oneTrillionTokens(token));

        // Ensure user isn't zero address
        vm.assume(args.user != address(0));

        // Switch to user
        _useNewSender(args.user);

        // Deal tokens in to user
        deal(address(token), args.user, args.tokensOut);

        // Approve tokens in to market proxy
        token.approve(address(marketProxy), args.tokensOut);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Buy
        marketProxy.buy({
            buyer: args.user, outcomeIdx: args.outcomeIdx, tokensIn: args.tokensOut, sharesOut: args.sharesOut
        });

        // Bound shares in
        args.sharesIn =
            bound(args.sharesIn, deployment.gateway.MIN_SHARES_DELTA(), marketProxy.totalSupply(args.outcomeIdx));

        // Get max shares in
        uint256 maxSharesIn = maxSharesIn(marketProxy, deployment.gateway, args.outcomeIdx);

        // If 0 < new outcome supply < MIN_SHARES_DELTA
        if (args.sharesIn != args.sharesOut && args.sharesIn > maxSharesIn) {
            // Re-bound shares in
            if (deployment.gateway.MIN_SHARES_DELTA() > maxSharesIn) {
                args.sharesIn = marketProxy.totalSupply(args.outcomeIdx);
            } else {
                args.sharesIn = bound(args.sharesIn, deployment.gateway.MIN_SHARES_DELTA(), maxSharesIn);
            }
        }

        // Try to quote sell exact in
        try deployment.gateway
            .quoteSellExactIn({
                marketProxy: marketProxy, outcomeIdx: args.outcomeIdx, sharesIn: args.sharesIn
            }) returns (
            uint256 expectedTokensOut, uint256, uint256
        ) {
            // Bound tokens out
            args.tokensOut = bound(args.tokensOut, 1, expectedTokensOut);

            // Calculate expectations
            SellExpectations memory expectations =
                _buildExpectations(args.user, args.outcomeIdx, args.tokensOut, args.sharesIn);

            // Expect event emission
            vm.expectEmit(true, true, true, true);
            emit ILmsrMarket.Sell(args.user, args.outcomeIdx, args.sharesIn, args.tokensOut);

            // Sell
            marketProxy.sell({
                seller: args.user, outcomeIdx: args.outcomeIdx, tokensOut: args.tokensOut, sharesIn: args.sharesIn
            });

            // Refresh market
            ILmsrMarket.Market memory market = marketProxy.getMarket();

            // Validate
            assertEq(market.expSum, expectations.marketExpSum, "market.exp != expectedMarketExp");
            assertEq(market.pool, expectations.marketPool, "market.pool != expectedMarketPool");
            assertEq(
                market.tradingFees, expectations.marketTradingFees, "market.tradingFees != expectedMarketTradingFees"
            );
            assertEq(
                marketProxy.totalSupply(args.outcomeIdx),
                expectations.outcomeSupply,
                "marketProxy.totalSupply(outcomeIdx) != expectedOutcomeSupply"
            );
            assertEq(
                marketProxy.balanceOf(args.user, args.outcomeIdx),
                expectations.outcomeBalance,
                "marketProxy.balanceOf(user, outcomeIdx) != expectedOutcomeBalance"
            );
            assertEq(token.balanceOf(args.user), expectations.userTokens, "token.balanceOf(user) != expectedUserTokens");
            assertEq(
                token.balanceOf(address(marketProxy)),
                expectations.marketTokens,
                "token.balanceOf(address(marketProxy)) != expectedMarketTokens"
            );
        } catch (bytes memory err) {
            // Ensure error is expected
            _handleCatch(err, _quoteSellExactInAllowedErrors());
        }
    }

    function _buildExpectations(address user, uint256 outcomeIdx, uint256 tokensOut, uint256 sharesIn)
        internal
        view
        returns (SellExpectations memory expectations)
    {
        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Calculate gross tokens out and fee amount
        (uint256 grossTokensOut, uint256 feeAmount) = tokensOut.addFee(market.config.tradingFee);

        // Snapshot the current outcome supply
        uint256 currentSupply = marketProxy.totalSupply(outcomeIdx);
        uint256 expectedOutcomeSupply = currentSupply - sharesIn;

        return SellExpectations({
            marketExpSum: market.expSum + LmsrMath.outcomeExp(market.config.b, expectedOutcomeSupply)
                - LmsrMath.outcomeExp(market.config.b, currentSupply),
            marketPool: market.pool - grossTokensOut,
            marketTradingFees: market.tradingFees + feeAmount,
            outcomeSupply: expectedOutcomeSupply,
            outcomeBalance: marketProxy.balanceOf(user, outcomeIdx) - sharesIn,
            userTokens: token.balanceOf(user) + tokensOut,
            marketTokens: token.balanceOf(address(marketProxy)) - tokensOut
        });
    }
}
