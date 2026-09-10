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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LmsrMarket_Buy_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;
    using Math for uint256;

    // Tests
    function testFuzz_Buy_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
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
        marketProxy.buy({buyer: user, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});
    }

    function testFuzz_Buy_MarketNotOpen_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
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
        marketProxy.buy({buyer: user, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});
    }

    function testFuzz_Buy_InvalidBuy_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

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

        // Keep tokens in below required tokens in
        tokensIn = bound(tokensIn, _minTokensIn({marketProxy_: marketProxy}), requiredTokensIn - 1);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.InvalidBuy.selector));

        // Buy
        marketProxy.buy({buyer: user, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});
    }

    // Note: To solve stack depth issues
    struct BuyArgs {
        uint256 outcomeIdx;
        uint256 tokensIn;
        uint256 sharesOut;
        address user;
    }

    // Note: To solve stack depth issues
    struct BuyExpectations {
        uint256 marketExpSum;
        uint256 marketPool;
        uint256 marketTradingFees;
        uint256 outcomeSupply;
        uint256 outcomeBalance;
        uint256 userTokens;
        uint256 marketTokens;
    }

    function testFuzz_Buy_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        BuyArgs memory args
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
        args.tokensIn = bound(args.tokensIn, requiredTokensIn, 1_000_000_000_000 * (10 ** token.decimals()));

        // Ensure user isn't zero address
        vm.assume(args.user != address(0));

        // Switch to user
        _useNewSender(args.user);

        // Deal tokens in to user
        deal(address(token), args.user, args.tokensIn);

        // Approve tokens in to market proxy
        token.approve(address(marketProxy), args.tokensIn);

        // Calculate expectations
        BuyExpectations memory expectations =
            _buildExpectations(args.user, args.outcomeIdx, args.tokensIn, args.sharesOut);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ILmsrMarket.Buy(args.user, args.outcomeIdx, args.tokensIn, args.sharesOut);

        // Buy
        marketProxy.buy({
            buyer: args.user, outcomeIdx: args.outcomeIdx, tokensIn: args.tokensIn, sharesOut: args.sharesOut
        });

        // Refresh market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Validate
        assertEq(market.expSum, expectations.marketExpSum, "market.exp != expectedMarketExp");
        assertEq(market.pool, expectations.marketPool, "market.pool != expectedMarketPool");
        assertEq(market.tradingFees, expectations.marketTradingFees, "market.tradingFees != expectedMarketTradingFees");
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
    }

    function _buildExpectations(address user, uint256 outcomeIdx, uint256 tokensIn, uint256 sharesOut)
        internal
        view
        returns (BuyExpectations memory expectations)
    {
        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Calculate net tokens in and fee amount
        (uint256 netTokensIn, uint256 feeAmount) = tokensIn.deductFee(market.config.tradingFee);

        // Snapshot the current outcome supply
        uint256 currentSupply = marketProxy.totalSupply(outcomeIdx);
        uint256 expectedOutcomeSupply = currentSupply + sharesOut;

        return BuyExpectations({
            marketExpSum: market.expSum + LmsrMath.outcomeExp(market.config.b, expectedOutcomeSupply)
                - LmsrMath.outcomeExp(market.config.b, currentSupply),
            marketPool: market.pool + netTokensIn,
            marketTradingFees: market.tradingFees + feeAmount,
            outcomeSupply: expectedOutcomeSupply,
            outcomeBalance: marketProxy.balanceOf(user, outcomeIdx) + sharesOut,
            userTokens: token.balanceOf(user) - tokensIn,
            marketTokens: token.balanceOf(address(marketProxy)) + tokensIn
        });
    }
}
