// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";

contract LmsrMarket_Transfer_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests
    function testFuzz_Transfer_ReceiverIsMarket_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address caller,
        uint256 id,
        uint256 amount
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
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.CannotTransferSharesToMarket.selector));

        // Transfer
        marketProxy.transfer({receiver: address(marketProxy), id: id, amount: amount});
    }

    function testFuzz_Transfer_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address sender,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        address receiver
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
        sharesOut = bound(sharesOut, deployment.gateway.MIN_SHARES_DELTA(), _maxSharesOut(marketProxy, outcomeIdx));

        // Quote Buy Exact Out
        try deployment.gateway
        .quoteBuyExactOut({marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut}) returns (
            uint256 tokensIn, uint256, uint256
        ) {
            // Bound max tokens in
            maxTokensIn = bound(maxTokensIn, tokensIn, type(uint256).max);

            // Mint tokens to sender
            deal(address(token), sender, maxTokensIn);

            // Ensure sender is not the zero address
            vm.assume(sender != address(0));

            // Switch to sender
            _useNewSender(sender);

            // Sender approves max tokens in
            token.approve(address(marketProxy), maxTokensIn);

            // Sender buys shares
            deployment.gateway
                .buyExactOut({
                    marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut, maxTokensIn: maxTokensIn
                });

            // Ensure receiver is not the zero address
            vm.assume(receiver != address(0));

            // Ensure receiver is not the sender
            vm.assume(receiver != sender);

            // Get vars before
            uint256 senderSharesBefore = marketProxy.balanceOf(sender, outcomeIdx);
            uint256 receiverSharesBefore = marketProxy.balanceOf(receiver, outcomeIdx);
            uint256 outcomeTotalSupplyBefore = marketProxy.totalSupply(outcomeIdx);

            // Sender transfers shares to receiver
            marketProxy.transfer({receiver: receiver, id: outcomeIdx, amount: sharesOut});

            // Validate
            assertEq(
                marketProxy.balanceOf(sender, outcomeIdx),
                senderSharesBefore - sharesOut,
                "unexpected sender shares balance"
            );
            assertEq(
                marketProxy.balanceOf(receiver, outcomeIdx),
                receiverSharesBefore + sharesOut,
                "unexpected receiver shares balance"
            );
            assertEq(marketProxy.totalSupply(outcomeIdx), outcomeTotalSupplyBefore, "unexpected outcome total supply");

            // Expect Revert
        } catch (bytes memory reason) {
            _handleCatch(reason, _quoteBuyExactOutAllowedErrors());
        }
    }
}
