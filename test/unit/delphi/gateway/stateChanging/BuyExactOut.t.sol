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

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract LmsrGateway_BuyExactOut_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Tests
    function testFuzz_BuyExactOut_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn
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

        // Buy exact out
        freshGateway.buyExactOut({
            marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut, maxTokensIn: maxTokensIn
        });
    }

    function testFuzz_BuyExactOut_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn
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

        // Buy exact out
        deployment.gateway
            .buyExactOut({
                marketProxy: ILmsrMarket(fakeMarketProxy),
                outcomeIdx: outcomeIdx,
                sharesOut: sharesOut,
                maxTokensIn: maxTokensIn
            });
    }

    function testFuzz_BuyExactOut_TokensInExceedMaxTokensIn_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
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
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        // Set max tokens in below the required tokens in
        maxTokensIn = bound(maxTokensIn, 0, tokensIn - 1);

        // Switch to user
        _useNewSender(user);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.TokensInExceedMaxTokensIn.selector, tokensIn, maxTokensIn)
        );

        // Buy exact out
        deployment.gateway
            .buyExactOut({
                marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut, maxTokensIn: maxTokensIn
            });
    }

    function testFuzz_BuyExactOut_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure user is a clean address
        vm.assume(user != address(0));
        vm.assume(user != address(marketProxy));

        // Bound outcome idx
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: outcomeIdx})
        );

        // Quote buy
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, outcomeIdx, sharesOut);

        // Set max tokens in at least the required tokens in
        maxTokensIn = bound(maxTokensIn, tokensIn, _oneTrillionTokens(token));

        // Switch to user
        _useNewSender(user);

        // Deal & approve tokens to the market proxy (the market pulls from the buyer)
        deal(address(token), user, maxTokensIn);
        token.approve(address(marketProxy), maxTokensIn);

        // Calculate expectations
        uint256 expectedUserTokens = token.balanceOf(user) - tokensIn;
        uint256 expectedMarketTokens = token.balanceOf(address(marketProxy)) + tokensIn;
        uint256 expectedOutcomeBalance = marketProxy.balanceOf(user, outcomeIdx) + sharesOut;
        uint256 expectedOutcomeSupply = marketProxy.totalSupply(outcomeIdx) + sharesOut;

        // Expect event emission
        uint256 outcomeNewExp;
        uint256 newExpSum;
        {
            uint256 outcomeCurrentExp = marketProxy.getMarket().config.b.outcomeExp(marketProxy.totalSupply(outcomeIdx));
            outcomeNewExp = marketProxy.getMarket().config.b.outcomeExp(expectedOutcomeSupply);
            newExpSum = marketProxy.getMarket().expSum + outcomeNewExp - outcomeCurrentExp;
        }
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayBuy(marketProxy, user, outcomeIdx, tokensIn, sharesOut, outcomeNewExp, newExpSum);

        // Buy exact out
        (uint256 returnedTokensIn,,) = deployment.gateway
            .buyExactOut({
                marketProxy: marketProxy, outcomeIdx: outcomeIdx, sharesOut: sharesOut, maxTokensIn: maxTokensIn
            });

        // Validate
        assertEq(returnedTokensIn, tokensIn, "returnedTokensIn != tokensIn");
        assertEq(token.balanceOf(user), expectedUserTokens, "user token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), expectedMarketTokens, "market token balance mismatch");
        assertEq(marketProxy.balanceOf(user, outcomeIdx), expectedOutcomeBalance, "outcome balance mismatch");
        assertEq(marketProxy.totalSupply(outcomeIdx), expectedOutcomeSupply, "outcome supply mismatch");
    }
}
