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

contract LmsrMarket_TransferKeeperFee_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests
    function testFuzz_TransferKeeperFee_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address keeper,
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

        // Transfer keeper fee
        marketProxy.transferKeeperFee({keeper: keeper});
    }

    function testFuzz_TransferKeeperFee_MarketNotAwaitingSettlement_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address keeper
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

        // Transfer keeper fee
        marketProxy.transferKeeperFee({keeper: keeper});
    }

    function testFuzz_TransferKeeperFee_CannotResolveMarketYet_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address keeper,
        uint256 warpTime
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Warp inside the resolve-delay window: trading is closed (AWAITING_SETTLEMENT) but
        // resolution is not allowed yet (window is non-empty since resolveDelay >= MIN_RESOLVE_DELAY)
        ILmsrMarket.MarketConfig memory config = marketProxy.getMarket().config;
        warpTime = bound(warpTime, config.tradingDeadline + 1, config.earliestResolveTime - 1);
        vm.warp(warpTime);

        // Switch to gateway
        _useNewSender(address(deployment.gateway));

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.CannotResolveMarketYet.selector, warpTime, config.earliestResolveTime
            )
        );

        // Transfer keeper fee
        marketProxy.transferKeeperFee({keeper: keeper});
    }

    function testFuzz_TransferKeeperFee_KeeperFeeAlreadyPaid_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address keeper
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

        // Warp to earliest resolve time
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);

        if (delphiConfig.keeperFee > 0) {
            vm.assume(keeper != address(0));
        }

        // Transfer keeper fee
        marketProxy.transferKeeperFee({keeper: keeper});

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.KeeperFeeAlreadyPaid.selector));

        // Transfer keeper fee again
        marketProxy.transferKeeperFee({keeper: keeper});
    }

    function testFuzz_TransferKeeperFee_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address keeper
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

        // Warp to earliest resolve time
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);

        if (delphiConfig.keeperFee > 0) {
            vm.assume(keeper != address(0));
        }

        // Calculate expectations
        uint256 expectedMarketBalance = token.balanceOf(address(marketProxy)) - marketProxy.KEEPER_FEE();
        uint256 expectedKeeperBalance = token.balanceOf(keeper) + marketProxy.KEEPER_FEE();

        // Transfer keeper fee
        marketProxy.transferKeeperFee({keeper: keeper});

        // Validate
        assertTrue(marketProxy.keeperFeePaid(), "keeper fee not paid");
        assertEq(token.balanceOf(address(marketProxy)), expectedMarketBalance, "unexpected market balance");
        assertEq(token.balanceOf(keeper), expectedKeeperBalance, "unexpected keeper balance");
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.AWAITING_SETTLEMENT),
            "market status != AWAITING_SETTLEMENT"
        );
    }
}
