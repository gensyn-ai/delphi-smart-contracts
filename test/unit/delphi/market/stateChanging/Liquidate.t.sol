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
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract LmsrMarket_Liquidate_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Functions

    /// @dev Buys `sharesOut` of `outcomeIdx` for `buyer` (called while the market is OPEN, pranked as gateway).
    function _buy(address buyer, uint256 outcomeIdx, uint256 sharesOut) internal {
        // Quote buy
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        // Switch to buyer
        _useNewSender(buyer);

        // Deal & approve tokens in
        deal(address(token), buyer, tokensIn);
        token.approve(address(marketProxy), tokensIn);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Buy
        marketProxy.buy({buyer: buyer, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});
    }

    // Tests

    function testFuzz_Liquidate_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address liquidator,
        address caller
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

        // Liquidate
        marketProxy.liquidate({liquidator: liquidator, outcomeIndices: new uint256[](0)});
    }

    function testFuzz_Liquidate_MarketNotExpiredNorFailed_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address liquidator
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Switch to gateway (market is OPEN)
        _useNewSender(address(deployment.gateway));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.MarketNotExpiredNorFailed.selector, ILmsrMarketTypes.MarketStatus.OPEN
            )
        );

        // Liquidate
        marketProxy.liquidate({liquidator: liquidator, outcomeIndices: new uint256[](0)});
    }

    function testFuzz_Liquidate_OutcomeIndicesAreEmpty_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address liquidator
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp past the settlement deadline (so market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.OutcomeIndicesAreEmpty.selector));

        // Liquidate with an empty outcome indices array
        marketProxy.liquidate({liquidator: liquidator, outcomeIndices: new uint256[](0)});
    }

    function testFuzz_Liquidate_ZeroSharesIn_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address liquidator,
        uint256 outcomeIdx
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

        // Warp past the settlement deadline (so market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Build outcome indices array (liquidator owns no shares)
        uint256[] memory outcomeIndices = new uint256[](1);
        outcomeIndices[0] = outcomeIdx;

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMathErrors.ZeroSharesIn.selector));

        // Liquidate
        marketProxy.liquidate({liquidator: liquidator, outcomeIndices: outcomeIndices});
    }

    // Note: To solve stack depth issues
    struct LiquidateArgs {
        address liquidator;
        uint256 outcomeIdx;
        uint256 sharesOut;
        bool marketCreatorBlacklisted;
    }

    // Note: To solve stack depth issues
    struct LiquidateExpectations {
        uint256 totalTokensOut;
        uint256 liquidatorTokens;
        uint256 marketTokens;
        uint256 marketPool;
        uint256 marketShares;
        uint256 supply;
        uint256 liquidatorShares;
    }

    function testFuzz_Liquidate_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        LiquidateArgs memory args
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure liquidator is a clean EOA-like address
        vm.assume(args.liquidator != address(0));
        vm.assume(args.liquidator != marketProxy.marketCreator());

        // Bound outcome idx
        args.outcomeIdx = bound(args.outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        args.sharesOut = bound(
            args.sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: args.outcomeIdx})
        );

        // Buy winning shares for the liquidator
        _buy({buyer: args.liquidator, outcomeIdx: args.outcomeIdx, sharesOut: args.sharesOut});

        // Warp past the settlement deadline (so market is EXPIRED)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Blacklist market creator (if specified)
        if (args.marketCreatorBlacklisted) {
            // Switch to token admin
            _useNewSender(token.ADMIN());

            // Blacklist market creator
            token.blacklist(MARKET_CREATOR);
        }

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Flush all sweeps first, so that the liquidate call only transfers the liquidation payout
        // (when the market creator is blacklisted, their reward accrues as claimable instead)
        marketProxy.trySweep();

        // Record the market creator claimable (liquidate must leave it untouched while blacklisted)
        uint256 expectedMarketCreatorClaimable = marketProxy.marketCreatorClaimable();

        // Calculate expectations
        LiquidateExpectations memory expectations = _buildExpectations(args.liquidator, args.outcomeIdx);

        // Build outcome indices array
        uint256[] memory outcomeIndices = new uint256[](1);
        outcomeIndices[0] = args.outcomeIdx;

        // Build expected shares in array
        uint256[] memory expectedSharesIn = new uint256[](1);
        expectedSharesIn[0] = expectations.liquidatorShares;

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(marketProxy));
        emit ILmsrMarket.Liquidation(args.liquidator, outcomeIndices, expectedSharesIn, expectations.totalTokensOut);

        // Liquidate
        (uint256[] memory sharesIn, uint256 totalTokensOut) =
            marketProxy.liquidate({liquidator: args.liquidator, outcomeIndices: outcomeIndices});

        // Refresh market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Validate return values
        assertEq(sharesIn.length, 1, "sharesIn length mismatch");
        assertEq(sharesIn[0], expectations.liquidatorShares, "sharesIn[0] mismatch");
        assertEq(totalTokensOut, expectations.totalTokensOut, "totalTokensOut mismatch");

        // Validate balances
        assertEq(token.balanceOf(args.liquidator), expectations.liquidatorTokens, "liquidator token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), expectations.marketTokens, "market token balance mismatch");
        assertEq(market.pool, expectations.marketPool, "market pool mismatch");

        // Validate shares (transferred to the market, not burned)
        assertEq(marketProxy.balanceOf(args.liquidator, args.outcomeIdx), 0, "liquidator shares not pulled");
        assertEq(
            marketProxy.balanceOf(address(marketProxy), args.outcomeIdx),
            expectations.marketShares,
            "market shares mismatch"
        );
        assertEq(marketProxy.totalSupply(args.outcomeIdx), expectations.supply, "total supply should be unchanged");

        // Validate market creator reward
        assertEq(
            marketProxy.marketCreatorClaimable(), expectedMarketCreatorClaimable, "marketCreatorClaimable mismatch"
        );
        if (args.marketCreatorBlacklisted) {
            assertEq(token.balanceOf(marketProxy.marketCreator()), 0, "market creator token balance != 0");
        }
    }

    function _buildExpectations(address liquidator, uint256 outcomeIdx)
        internal
        view
        returns (LiquidateExpectations memory expectations)
    {
        // Get market + supply
        ILmsrMarket.Market memory market = marketProxy.getMarket();
        uint256 supply = marketProxy.totalSupply(outcomeIdx);
        uint256 liquidatorShares = marketProxy.balanceOf(liquidator, outcomeIdx);

        // Calculate expected total tokens out
        uint256 numeratorSum36 = liquidatorShares * LmsrMath.outcomeExp(market.config.b, supply);
        uint256 expectedTotalTokensOut = numeratorSum36.liquidatorTotalReward({
            currentExpSum: market.expSum, tokenDecimalScaler: marketProxy.TOKEN_DECIMAL_SCALER()
        });

        return LiquidateExpectations({
            totalTokensOut: expectedTotalTokensOut,
            liquidatorTokens: token.balanceOf(liquidator) + expectedTotalTokensOut,
            marketTokens: token.balanceOf(address(marketProxy)) - expectedTotalTokensOut,
            marketPool: market.pool - expectedTotalTokensOut,
            marketShares: marketProxy.balanceOf(address(marketProxy), outcomeIdx) + liquidatorShares,
            supply: supply,
            liquidatorShares: liquidatorShares
        });
    }
}
