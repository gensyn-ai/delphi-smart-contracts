// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

contract LmsrGateway_SellExactIn_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Functions

    /// @dev Buys `sharesOut` of `outcomeIdx` for `buyer` through the gateway.
    function _buy(address buyer, uint256 outcomeIdx, uint256 sharesOut) internal {
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        _useNewSender(buyer);
        deal(address(token), buyer, tokensIn);
        token.approve(address(marketProxy), tokensIn);
        deployment.gateway
            .buyExactOut({
                marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut, maxTokensIn: tokensIn
            });
    }

    /// @dev Re-bounds shares in to avoid leaving 0 < newSupply < MIN_SHARES_DELTA.
    function _boundSharesIn(uint256 outcomeIdx, uint256 sharesIn, uint256 sharesOut) internal view returns (uint256) {
        // Bound shares in
        sharesIn = bound(sharesIn, deployment.gateway.MIN_SHARES_DELTA(), marketProxy.totalSupply(outcomeIdx));

        // Get max shares in
        uint256 maxSharesIn = maxSharesIn(marketProxy, deployment.gateway, outcomeIdx);

        if (sharesIn != sharesOut && sharesIn > maxSharesIn) {
            if (deployment.gateway.MIN_SHARES_DELTA() > maxSharesIn) {
                sharesIn = marketProxy.totalSupply(outcomeIdx);
            } else {
                sharesIn = bound(sharesIn, deployment.gateway.MIN_SHARES_DELTA(), maxSharesIn);
            }
        }

        // Return shares in
        return sharesIn;
    }

    // Tests

    function testFuzz_SellExactIn_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesIn,
        uint256 minTokensOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Deploy a fresh, uninitialized gateway
        LmsrGateway freshGateway = new LmsrGateway(token, GATEWAY_OWNER);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.GatewayNotInitialized.selector));

        // Sell exact in
        freshGateway.sellExactIn({
            marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesIn, minTokensOut: minTokensOut
        });
    }

    function testFuzz_SellExactIn_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        uint256 outcomeIdx,
        uint256 sharesIn,
        uint256 minTokensOut
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure the fake market proxy is not a real one
        vm.assume(!deployment.factory.marketProxyExists(fakeMarketProxy));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.MarketProxyNotDeployedByFactory.selector, fakeMarketProxy)
        );

        // Sell exact in
        deployment.gateway
            .sellExactIn({
                marketProxy: ILmsrMarket(fakeMarketProxy),
                outcomeIdx: outcomeIdx,
                sharesIn: sharesIn,
                minTokensOut: minTokensOut
            });
    }

    function testFuzz_SellExactIn_TokensOutBelowMinTokensOut_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 sharesIn,
        uint256 minTokensOut,
        address seller
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure seller is a clean address
        vm.assume(seller != address(0));
        vm.assume(seller != address(marketProxy));

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out (to buy)
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Buy shares for the seller (so they can be sold)
        _buy({buyer: seller, outcomeIdx: outcomeIdx, sharesOut: sharesOut});

        // Bound shares in
        sharesIn = _boundSharesIn(outcomeIdx, sharesIn, sharesOut);

        // Try to quote sell exact in
        try deployment.gateway
        .quoteSellExactIn({marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesIn}) returns (
            uint256 tokensOut, uint256, uint256
        ) {
            // Set min tokens out above the quoted tokens out
            minTokensOut = bound(minTokensOut, tokensOut + 1, type(uint256).max);

            // Switch to seller
            _useNewSender(seller);

            // Expect Revert
            vm.expectRevert(
                abi.encodeWithSelector(ILmsrGatewayErrors.TokensOutBelowMinTokensOut.selector, tokensOut, minTokensOut)
            );

            // Sell exact in
            deployment.gateway
                .sellExactIn({
                    marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesIn, minTokensOut: minTokensOut
                });
        } catch (bytes memory err) {
            // Ensure error is expected
            _handleCatch(err, _quoteSellExactInAllowedErrors());
        }
    }

    struct SellExactInExpectations {
        uint256 sellerTokensAfter;
        uint256 marketTokensAfter;
        uint256 outcomeBalanceAfter;
        uint256 outcomeSupplyAfter;
    }

    function testFuzz_SellExactIn_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 sharesIn,
        uint256 minTokensOut,
        address seller
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure seller is a clean address
        vm.assume(seller != address(0));
        vm.assume(seller != address(marketProxy));

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out (to buy)
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Buy shares for the seller
        _buy({buyer: seller, outcomeIdx: outcomeIdx, sharesOut: sharesOut});

        // Bound shares in
        sharesIn = _boundSharesIn(outcomeIdx, sharesIn, sharesOut);

        // Try to quote sell exact in
        try deployment.gateway
        .quoteSellExactIn({marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesIn}) returns (
            uint256 tokensOut, uint256 outcomeNewExp, uint256 newExpSum
        ) {
            // Set min tokens out at most the quoted tokens out
            minTokensOut = bound(minTokensOut, 0, tokensOut);

            // Calculate expectations
            SellExactInExpectations memory expectations =
                _buildExpectations({seller: seller, outcomeIdx: outcomeIdx, sharesIn: sharesIn, tokensOut: tokensOut});

            // Switch to seller
            _useNewSender(seller);

            // Expect event emission
            vm.expectEmit(true, true, true, true, address(deployment.gateway));
            emit ILmsrGateway.GatewaySell(
                marketProxy, seller, outcomeIdx, sharesIn, tokensOut, outcomeNewExp, newExpSum
            );

            // Sell exact in
            (uint256 returnedTokensOut,,) = deployment.gateway
                .sellExactIn({
                    marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesIn, minTokensOut: minTokensOut
                });

            // Validate
            assertEq(returnedTokensOut, tokensOut, "returnedTokensOut != tokensOut");
            assertEq(token.balanceOf(seller), expectations.sellerTokensAfter, "seller token balance mismatch");
            assertEq(
                token.balanceOf(address(marketProxy)), expectations.marketTokensAfter, "market token balance mismatch"
            );
            assertEq(
                marketProxy.balanceOf(seller, outcomeIdx), expectations.outcomeBalanceAfter, "outcome balance mismatch"
            );
            assertEq(marketProxy.totalSupply(outcomeIdx), expectations.outcomeSupplyAfter, "outcome supply mismatch");
        } catch (bytes memory err) {
            // Ensure error is expected
            _handleCatch(err, _quoteSellExactInAllowedErrors());
        }
    }

    function _buildExpectations(address seller, uint256 outcomeIdx, uint256 sharesIn, uint256 tokensOut)
        internal
        view
        returns (SellExactInExpectations memory expectations)
    {
        return SellExactInExpectations({
            sellerTokensAfter: token.balanceOf(seller) + tokensOut,
            marketTokensAfter: token.balanceOf(address(marketProxy)) - tokensOut,
            outcomeBalanceAfter: marketProxy.balanceOf(seller, outcomeIdx) - sharesIn,
            outcomeSupplyAfter: marketProxy.totalSupply(outcomeIdx) - sharesIn
        });
    }
}
