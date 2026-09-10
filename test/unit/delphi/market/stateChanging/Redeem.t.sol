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

contract LmsrMarket_Redeem_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Functions

    /// @dev Buys `sharesOut` of `outcomeIdx` for `buyer` (called while the market is OPEN, pranked as gateway).
    function _buy(address buyer, uint256 outcomeIdx, uint256 sharesOut) internal {
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        _useNewSender(buyer);
        deal(address(token), buyer, tokensIn);
        token.approve(address(marketProxy), tokensIn);

        _useNewSender(address(deployment.gateway));
        marketProxy.buy({buyer: buyer, outcomeIdx: outcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});
    }

    // Tests
    function testFuzz_Redeem_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address redeemer,
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

        // Redeem
        marketProxy.redeem({redeemer: redeemer});
    }

    function testFuzz_Redeem_MarketNotSettled_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address redeemer
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

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.WrongMarketStatus.selector,
                marketProxy.marketStatus(),
                uint8(ILmsrMarketTypes.MarketStatus.SETTLED)
            )
        );

        // Redeem
        marketProxy.redeem({redeemer: redeemer});
    }

    function testFuzz_Redeem_WinningSharesInLessThanTokenDecimalScaler_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address redeemer,
        uint256 outcomeIdx,
        address oracleFeeRecipient
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound winning outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Todo: Buy shares, so that redeemer winning shares aren't always zero

        // Advance time (so that market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // If oracle fee is positive
        if (deployment.implementation.ORACLE_FEE() > 0) {
            // Ensure oracle fee recipient is not zero address
            vm.assume(oracleFeeRecipient != address(0));
        }

        // Settle market (so that market is SETTLED)
        marketProxy.settleMarket({winningOutcomeIdx: outcomeIdx, oracleFeeRecipient: oracleFeeRecipient});

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.WinningSharesInAreLessThanTokenDecimalScaler.selector,
                0,
                deployment.implementation.TOKEN_DECIMAL_SCALER()
            )
        );

        // Redeem
        marketProxy.redeem({redeemer: redeemer});
    }

    function testFuzz_Redeem_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address redeemer,
        uint256 winningOutcomeIdx,
        uint256 sharesOut,
        address oracleFeeRecipient
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure redeemer is a clean address
        vm.assume(redeemer != address(0));
        vm.assume(redeemer != address(marketProxy));

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out: must be at least the token decimal scaler, so that the redeemer reward is positive
        uint256 minShares = deployment.gateway.MIN_SHARES_DELTA();
        if (marketProxy.TOKEN_DECIMAL_SCALER() > minShares) {
            minShares = marketProxy.TOKEN_DECIMAL_SCALER();
        }
        sharesOut =
            bound(sharesOut, minShares, _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: winningOutcomeIdx}));

        // Buy winning shares for the redeemer
        _buy({buyer: redeemer, outcomeIdx: winningOutcomeIdx, sharesOut: sharesOut});

        // Advance time (so that market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // If oracle fee is positive, ensure oracle fee recipient is not the zero address
        if (deployment.implementation.ORACLE_FEE() > 0) {
            vm.assume(oracleFeeRecipient != address(0));
        }

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Settle market (so that market is SETTLED)
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: oracleFeeRecipient});

        // Get redeemer winning shares
        uint256 winningSharesIn = marketProxy.balanceOf(redeemer, winningOutcomeIdx);

        // Calculate expected tokens out (rounded down against the user)
        uint256 expectedTokensOut = winningSharesIn / marketProxy.TOKEN_DECIMAL_SCALER();

        // Record balances
        uint256 expectedRedeemerTokens = token.balanceOf(redeemer) + expectedTokensOut;
        uint256 expectedMarketTokens = token.balanceOf(address(marketProxy)) - expectedTokensOut;
        uint256 expectedMarketPool = marketProxy.getMarket().pool - expectedTokensOut;
        uint256 expectedMarketShares = marketProxy.balanceOf(address(marketProxy), winningOutcomeIdx) + winningSharesIn;

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(marketProxy));
        emit ILmsrMarket.Redemption(redeemer, winningSharesIn, expectedTokensOut);

        // Redeem
        (uint256 sharesIn, uint256 tokensOut) = marketProxy.redeem({redeemer: redeemer});

        // Validate return values
        assertEq(sharesIn, winningSharesIn, "sharesIn != winningSharesIn");
        assertEq(tokensOut, expectedTokensOut, "tokensOut != expectedTokensOut");

        // Validate balances
        assertEq(token.balanceOf(redeemer), expectedRedeemerTokens, "redeemer token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), expectedMarketTokens, "market token balance mismatch");
        assertEq(marketProxy.getMarket().pool, expectedMarketPool, "market pool mismatch");

        // Validate shares (pulled from redeemer to the market)
        assertEq(marketProxy.balanceOf(redeemer, winningOutcomeIdx), 0, "redeemer shares not pulled");
        assertEq(
            marketProxy.balanceOf(address(marketProxy), winningOutcomeIdx),
            expectedMarketShares,
            "market shares mismatch"
        );
    }
}
