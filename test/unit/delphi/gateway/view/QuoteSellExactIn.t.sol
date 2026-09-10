// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";

contract LmsrGateway_QuoteSellExactIn_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Functions

    // Tests

    function testFuzz_QuoteSellExactIn_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesIn
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

        // Quote sell exact in
        freshGateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        uint256 outcomeIdx,
        uint256 sharesIn
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

        // Quote sell exact in
        deployment.gateway.quoteSellExactIn(ILmsrMarket(fakeMarketProxy), outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_MarketNotOpen_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesIn
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp past the trading deadline (so the market is no longer OPEN)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.MarketNotOpen.selector));

        // Quote sell exact in
        deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_OutcomeIsOutOfBounds_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesIn
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound outcome idx out of the configured range
        uint256 outcomeCount = marketProxy.getMarket().config.outcomeCount;
        outcomeIdx = bound(outcomeIdx, outcomeCount, type(uint256).max);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrMarketErrors.OutcomeIsOutOfBounds.selector, outcomeIdx, outcomeCount)
        );

        // Quote sell exact in
        deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_SharesInBelowMinDelta_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesIn
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

        // Bound shares in below the minimum delta
        sharesIn = bound(sharesIn, 0, deployment.gateway.MIN_SHARES_DELTA() - 1);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrGatewayErrors.SharesInBelowMinDelta.selector, sharesIn, deployment.gateway.MIN_SHARES_DELTA()
            )
        );

        // Quote sell exact in
        deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_SharesInExceedSupply_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesIn
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

        // Get outcome supply (zero, since no trades occurred)
        uint256 supply = marketProxy.totalSupply(outcomeIdx);

        // Bound shares in above the supply (and at least the minimum delta)
        sharesIn = bound(sharesIn, deployment.gateway.MIN_SHARES_DELTA(), type(uint256).max);
        vm.assume(sharesIn > supply);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMathErrors.SharesInExceedSupply.selector, sharesIn, supply));

        // Quote sell exact in
        deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_OutcomeSupplyBelowMinDelta_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 newSupply,
        address buyer
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure buyer is a clean address
        vm.assume(buyer != address(0));
        vm.assume(buyer != address(marketProxy));

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Ensure there is room to buy at least twice the minimum delta
        uint256 minDelta = deployment.gateway.MIN_SHARES_DELTA();
        vm.assume(_maxSharesOut(marketProxy, outcomeIdx) >= 2 * minDelta);

        // Buy shares (so the supply is large enough to leave a tiny remainder)
        sharesOut = bound(sharesOut, 2 * minDelta, _maxSharesOut(marketProxy, outcomeIdx));
        _buyViaGateway({
            buyer: buyer,
            gateway: deployment.gateway,
            marketProxy: marketProxy,
            token: token,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut
        });

        // Choose a new supply in (0, minDelta) and derive the shares in
        uint256 supply = marketProxy.totalSupply(outcomeIdx);
        newSupply = bound(newSupply, 1, minDelta - 1);
        uint256 sharesIn = supply - newSupply;

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.OutcomeNewSupplyBelowMinDelta.selector, newSupply, minDelta)
        );

        // Quote sell exact in
        deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);
    }

    function testFuzz_QuoteSellExactIn_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 sharesIn,
        address buyer
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure buyer is a clean address
        vm.assume(buyer != address(0));
        vm.assume(buyer != address(marketProxy));

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Buy shares (so there is supply to sell)
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );
        _buyViaGateway({
            buyer: buyer,
            gateway: deployment.gateway,
            marketProxy: marketProxy,
            token: token,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut
        });

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

        // Quote sell exact in
        try deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn) returns (
            uint256 tokensOut, uint256, uint256
        ) {
            (uint256 tokensOut2,,) = deployment.gateway.quoteSellExactIn(marketProxy, outcomeIdx, sharesIn);

            // Validate (quotes are positive and deterministic)
            assertGt(tokensOut, 0, "tokensOut != positive");
            assertEq(tokensOut, tokensOut2, "quote is not deterministic");
        } catch (bytes memory err) {
            // Ensure error is expected
            _handleCatch(err, _quoteSellExactInAllowedErrors());
        }
    }
}
