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

contract LmsrMarket_FailMarket_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests
    function testFuzz_FailMarket_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
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

        // Fail market
        marketProxy.failMarket();
    }

    function testFuzz_FailMarket_MarketNotAwaitingSettlement_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
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
                uint8(ILmsrMarketTypes.MarketStatus.AWAITING_SETTLEMENT)
            )
        );

        // Fail market
        marketProxy.failMarket();
    }

    /// @dev The keeper fee left the proxy when `resolveMarket` ran, so the sweep triggered by
    ///      failing the market must NOT re-credit it to the creator.
    function testFuzz_FailMarket_AfterResolution_DoesNotSweepKeeperFee(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp to earliest resolve time
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);

        // Make the relayer lock-only (it receives the resolution request but does not respond synchronously)
        oracleRelayer.setLockOnly(true);

        // Switch to keeper
        _useNewSender(KEEPER);

        // Resolve market (pays the keeper fee out of the proxy and locks settlement)
        deployment.gateway.resolveMarket(address(marketProxy));

        // Validate the keeper fee was paid
        assertTrue(marketProxy.keeperFeePaid(), "keeperFeePaid != true");
        assertEq(token.balanceOf(KEEPER), marketProxy.KEEPER_FEE(), "keeper token balance != KEEPER_FEE");

        // Calculate expectations (no trades occurred, so the whole pool plus the unpaid oracle fee
        // sweeps to the creator — but NOT the already-paid keeper fee)
        uint256 expectedCreatorTokens =
            token.balanceOf(MARKET_CREATOR) + marketProxy.getMarket().pool + marketProxy.ORACLE_FEE();

        // Switch to oracle relayer
        _useNewSender(address(oracleRelayer));

        // Fail market (through the gateway, as the oracle relayer would)
        deployment.gateway.failMarket(address(marketProxy));

        // Validate
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.FAILED), "market status != FAILED"
        );
        assertEq(token.balanceOf(MARKET_CREATOR), expectedCreatorTokens, "market creator token balance mismatch");
        assertEq(token.balanceOf(address(marketProxy)), 0, "market token balance != 0");
        assertEq(marketProxy.marketCreatorClaimable(), 0, "marketCreatorClaimable != 0");
        assertEq(token.balanceOf(KEEPER), marketProxy.KEEPER_FEE(), "keeper token balance changed");
    }

    function testFuzz_FailMarket_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        bool marketCreatorBlacklisted
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Skip time, so market is AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Calculate the market creator sweep amount (no trades happened, so the whole pool is swept)
        uint256 marketCreatorSweepAmount =
            marketProxy.getMarket().pool + marketProxy.KEEPER_FEE() + marketProxy.ORACLE_FEE();

        // Calculate expectations
        uint256 expectedMarketCreatorTokens;
        uint256 expectedMarketCreatorClaimable;

        // Blacklist market creator (if specified)
        if (marketCreatorBlacklisted) {
            // Switch to token admin
            _useNewSender(token.ADMIN());

            // Blacklist market creator
            token.blacklist(MARKET_CREATOR);

            // The sweep amount stays in the market as a claimable balance
            expectedMarketCreatorTokens = 0;
            expectedMarketCreatorClaimable = marketCreatorSweepAmount;
        } else {
            expectedMarketCreatorTokens = marketCreatorSweepAmount;
            expectedMarketCreatorClaimable = 0;
        }

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Fail market
        marketProxy.failMarket();

        // Validate
        assertTrue(marketProxy.marketFailed(), "market should be failed");
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.FAILED), "market status != FAILED"
        );
        assertEq(
            token.balanceOf(marketProxy.marketCreator()),
            expectedMarketCreatorTokens,
            "market creator token balance mismatch"
        );
        assertEq(
            marketProxy.marketCreatorClaimable(), expectedMarketCreatorClaimable, "marketCreatorClaimable mismatch"
        );
    }
}
