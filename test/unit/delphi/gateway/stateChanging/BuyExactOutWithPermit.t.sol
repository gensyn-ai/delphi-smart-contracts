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

contract LmsrGateway_BuyExactOutWithPermit_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Constants
    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // Functions

    /// @dev Builds the EIP-2612 signature for a permit over the test token.
    function _signPermit(uint256 pk, address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, token.nonces(owner), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(pk, digest);
    }

    // Tests

    function testFuzz_BuyExactOutWithPermit_GatewayNotInitialized_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
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

        // Buy exact out with permit
        freshGateway.buyExactOutWithPermit({
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut,
            maxTokensIn: maxTokensIn,
            deadline: deadline,
            v: v,
            r: r,
            s: s
        });
    }

    function testFuzz_BuyExactOutWithPermit_MarketProxyNotDeployedByFactory_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeMarketProxy,
        BuyExactOutWithPermitArgs memory args,
        uint8 v,
        bytes32 r,
        bytes32 s
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

        // Buy exact out with permit
        deployment.gateway
            .buyExactOutWithPermit({
                marketProxy: ILmsrMarket(fakeMarketProxy),
                outcomeIdx: args.outcomeIdx,
                sharesOut: args.sharesOut,
                maxTokensIn: args.maxTokensIn,
                deadline: args.deadline,
                v: v,
                r: r,
                s: s
            });
    }

    function testFuzz_BuyExactOutWithPermit_ExpiredSignature_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        uint256 deadline,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Set the deadline in the past
        deadline = bound(deadline, 0, block.timestamp - 1);
        maxTokensIn = bound(maxTokensIn, 1, type(uint256).max);

        // Switch to user
        _useNewSender(user);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.AllowanceTooLow.selector, 0, maxTokensIn));

        // Buy exact out with permit (signature irrelevant: the deadline check comes first)
        deployment.gateway
            .buyExactOutWithPermit({
                marketProxy: marketProxy,
                outcomeIdx: outcomeIdx,
                sharesOut: sharesOut,
                maxTokensIn: maxTokensIn,
                deadline: deadline,
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            });
    }

    function testFuzz_BuyExactOutWithPermit_InvalidSignature_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx,
        uint256 sharesOut,
        uint256 maxTokensIn,
        uint256 deadline,
        uint256 pkSeed,
        address user
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Derive a signer that is not the owner
        uint256 pk = _randomPk(pkSeed);
        address signer = vm.addr(pk);
        vm.assume(user != signer);

        // Set the deadline in the future
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        maxTokensIn = bound(maxTokensIn, 1, type(uint256).max);

        // Sign the permit for owner=user (so the deadline check passes but the recovered signer differs)
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(pk, user, address(marketProxy), maxTokensIn, deadline);

        // Switch to user
        _useNewSender(user);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.AllowanceTooLow.selector, 0, maxTokensIn));

        // Buy exact out with permit
        deployment.gateway
            .buyExactOutWithPermit({
                marketProxy: marketProxy,
                outcomeIdx: outcomeIdx,
                sharesOut: sharesOut,
                maxTokensIn: maxTokensIn,
                deadline: deadline,
                v: v,
                r: r,
                s: s
            });
    }

    // Note: To solve stack depth issues
    struct BuyExactOutWithPermitArgs {
        uint256 buyerPkSeed;
        uint256 outcomeIdx;
        uint256 sharesOut;
        uint256 maxTokensIn;
        uint256 deadline;
    }

    // Note: To solve stack depth issues
    struct BuyExactOutWithPermitExpectations {
        uint256 buyerTokensAfter;
        uint256 marketTokensAfter;
        uint256 buyerOutcomeBalanceAfter;
        uint256 marketAllowanceAfter;
    }

    function testFuzz_BuyExactOutWithPermit_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        BuyExactOutWithPermitArgs memory args
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Test
        _testBuyExactOutWithPermit_Success(args);
    }

    function _testBuyExactOutWithPermit_Success(BuyExactOutWithPermitArgs memory args) internal {
        // Get random pk
        uint256 buyerPk = _randomPk(args.buyerPkSeed);

        // Derive buyer from pk
        address buyer = vm.addr(buyerPk);

        // Ensure buyer is not the market proxy
        vm.assume(buyer != address(marketProxy));

        // Bound outcome idx
        args.outcomeIdx = bound(args.outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Bound shares out
        args.sharesOut = bound(
            args.sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: args.outcomeIdx})
        );

        // Quote buy
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, args.outcomeIdx, args.sharesOut);

        // Set max tokens in at least the required tokens in
        args.maxTokensIn = bound(args.maxTokensIn, tokensIn, _oneTrillionTokens(token));

        // Set the deadline in the future
        args.deadline = bound(args.deadline, block.timestamp, type(uint256).max);

        // Deal tokens to the user (the permit grants the allowance, no manual approve)
        deal(address(token), buyer, args.maxTokensIn);

        // Calculate expectations
        BuyExactOutWithPermitExpectations memory expectations =
            _buildExpectations(buyer, args.outcomeIdx, tokensIn, args.sharesOut, args.maxTokensIn);

        // Switch to user
        _useNewSender(buyer);

        // Expect event emission
        uint256 outcomeNewExp;
        uint256 newExpSum;
        {
            uint256 outcomeCurrentExp =
                marketProxy.getMarket().config.b.outcomeExp(marketProxy.totalSupply(args.outcomeIdx));
            outcomeNewExp =
                marketProxy.getMarket().config.b.outcomeExp(marketProxy.totalSupply(args.outcomeIdx) + args.sharesOut);
            newExpSum = marketProxy.getMarket().expSum + outcomeNewExp - outcomeCurrentExp;
        }
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.GatewayBuy(
            marketProxy, buyer, args.outcomeIdx, tokensIn, args.sharesOut, outcomeNewExp, newExpSum
        );

        // Buy exact out with permit
        uint256 returnedTokensIn = _signAndBuy({buyerPk: buyerPk, buyer: buyer, args: args});

        // Validate
        assertEq(returnedTokensIn, tokensIn, "returnedTokensIn != tokensIn");
        assertEq(token.balanceOf(buyer), expectations.buyerTokensAfter, "user token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), expectations.marketTokensAfter, "market token balance mismatch");
        assertEq(
            marketProxy.balanceOf(buyer, args.outcomeIdx),
            expectations.buyerOutcomeBalanceAfter,
            "outcome balance mismatch"
        );
        assertEq(token.allowance(buyer, address(marketProxy)), expectations.marketAllowanceAfter, "allowance mismatch");
    }

    function _signAndBuy(uint256 buyerPk, address buyer, BuyExactOutWithPermitArgs memory args)
        internal
        returns (uint256 returnedTokensIn)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(buyerPk, buyer, address(marketProxy), args.maxTokensIn, args.deadline);

        // Buy exact out with permit
        (returnedTokensIn,,) = deployment.gateway
            .buyExactOutWithPermit({
                marketProxy: marketProxy,
                outcomeIdx: args.outcomeIdx,
                sharesOut: args.sharesOut,
                maxTokensIn: args.maxTokensIn,
                deadline: args.deadline,
                v: v,
                r: r,
                s: s
            });
    }

    function _buildExpectations(
        address buyer,
        uint256 outcomeIdx,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 maxTokensIn
    ) internal view returns (BuyExactOutWithPermitExpectations memory expectations) {
        return BuyExactOutWithPermitExpectations({
            buyerTokensAfter: token.balanceOf(buyer) - tokensIn,
            marketTokensAfter: token.balanceOf(address(marketProxy)) + tokensIn,
            buyerOutcomeBalanceAfter: marketProxy.balanceOf(buyer, outcomeIdx) + sharesOut,
            marketAllowanceAfter: maxTokensIn - tokensIn
        });
    }
}
