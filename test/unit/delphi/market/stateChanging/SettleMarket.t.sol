// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract LmsrMarket_SettleMarket_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Tests
    function testFuzz_SettleMarket_CallerIsNotGateway_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient,
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

        // Settle market
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: oracleFeeRecipient});
    }

    function testFuzz_SettleMarket_MarketNotAwaitingSettlement_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient
        // address caller
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

        // Skip time, so market is not AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.WrongMarketStatus.selector,
                uint8(marketProxy.marketStatus()),
                uint8(ILmsrMarketTypes.MarketStatus.AWAITING_SETTLEMENT)
            )
        );

        // Settle market
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: oracleFeeRecipient});
    }

    function testFuzz_SettleMarket_WinningOutcomeOutOfBounds_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient
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

        // Skip time, so market is AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Ensure winning outcome idx is out of bounds
        winningOutcomeIdx = bound(winningOutcomeIdx, marketProxy.getMarket().config.outcomeCount, type(uint256).max);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.OutcomeIsOutOfBounds.selector,
                winningOutcomeIdx,
                marketProxy.getMarket().config.outcomeCount
            )
        );

        // Settle market
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: oracleFeeRecipient});
    }

    function testFuzz_SettleMarket_OracleFeeRecipientIsZeroAddress_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx
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

        // Skip time, so market is AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // Todo: Hardcode the ORACLE_FEE to zero, to improve coverage.
        if (marketProxy.ORACLE_FEE() > 0) {
            // Expect Revert
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }

        // Settle market
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: address(0)});
    }

    function testFuzz_SettleMarket_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 winningOutcomeIdx,
        address oracleFeeRecipient,
        bool marketCreatorBlacklisted
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

        // Skip time, so market is AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Bound winning outcome idx
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);

        // If there is an oracle fee
        if (marketProxy.ORACLE_FEE() > 0) {
            // ensure the oracle fee recipient is not the zero address
            vm.assume(oracleFeeRecipient != address(0));
        }

        // Ensure the oracle fee recipient is not the MARKET_CREATION_FEE_RECIPIENT nor the market creator
        vm.assume(oracleFeeRecipient != deployment.factory.MARKET_CREATION_FEE_RECIPIENT());
        vm.assume(oracleFeeRecipient != marketProxy.marketCreator());
        vm.assume(oracleFeeRecipient != marketProxy.TRADING_FEES_RECIPIENT());

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Calculate vars
        uint256 winningPayout = marketProxy.totalSupply(winningOutcomeIdx) / marketProxy.TOKEN_DECIMAL_SCALER();
        uint256 losingPayout = market.pool - winningPayout;
        uint256 tradingFeesRecipientTradingFeesCut = market.tradingFees
            .tradingFeesRecipientCut({tradingFeesRecipientPct: marketProxy.TRADING_FEES_RECIPIENT_PCT()});
        uint256 marketCreatorTradingFeesCut = market.tradingFees - tradingFeesRecipientTradingFeesCut;
        uint256 marketCreatorSettlementReward = losingPayout + marketCreatorTradingFeesCut;
        uint256 expectedMarketBalance;
        uint256 expectedMarketCreatorBalance;
        uint256 expectedMarketCreatorClaimable;

        // Blacklist market creator (if specified)
        if (marketCreatorBlacklisted) {
            // Switch to token admin
            _useNewSender(token.ADMIN());

            // Blacklist market creator
            token.blacklist(MARKET_CREATOR);

            // Set expected market balance (the settlement reward stays in the market as a claimable balance)
            expectedMarketBalance = token.balanceOf(address(marketProxy)) - marketProxy.ORACLE_FEE();

            // Set expected market creator balance and claimable
            expectedMarketCreatorBalance = 0;
            expectedMarketCreatorClaimable = marketCreatorSettlementReward;

            // Switch back to gateway (settleMarket is onlyGateway)
            _useNewSender(address(deployment.gateway));
        } else {
            // Set expected market balance
            expectedMarketBalance =
                token.balanceOf(address(marketProxy)) - marketProxy.ORACLE_FEE() - marketCreatorSettlementReward;

            // Set expected market creator balance and claimable
            expectedMarketCreatorBalance = marketCreatorSettlementReward;
            expectedMarketCreatorClaimable = 0;
        }

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(marketProxy));
        emit ILmsrMarket.MarketSettled(
            winningOutcomeIdx, losingPayout, tradingFeesRecipientTradingFeesCut, marketCreatorTradingFeesCut
        );

        // Settle market
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: oracleFeeRecipient});

        // Refresh market
        market = marketProxy.getMarket();

        // Validate
        assertEq(market.winningOutcomeIdx, winningOutcomeIdx, "market.winningOutcomeIdx != winningOutcomeIdx");
        assertEq(market.pool, winningPayout, "market.pool != winningPayout");
        assertEq(market.tradingFees, 0, "market.tradingFees != 0");
        assertEq(marketProxy.oracleFeePaid(), true, "marketProxy.oracleFeePaid != true");
        assertEq(
            token.balanceOf(marketProxy.TRADING_FEES_RECIPIENT()),
            tradingFeesRecipientTradingFeesCut,
            "TRADING_FEES_RECIPIENT token balance != tradingFeesRecipientTradingFeesCut"
        );
        assertEq(
            token.balanceOf(marketProxy.marketCreator()),
            expectedMarketCreatorBalance,
            "unexpected market creator balance"
        );
        assertEq(
            marketProxy.marketCreatorClaimable(), expectedMarketCreatorClaimable, "marketCreatorClaimable mismatch"
        );
        assertEq(
            token.balanceOf(oracleFeeRecipient),
            marketProxy.ORACLE_FEE(),
            "oracleFeeRecipient token balance != marketProxy.ORACLE_FEE()"
        );
        assertEq(token.balanceOf(address(marketProxy)), expectedMarketBalance);
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.SETTLED), "market status != SETTLED"
        );
    }
}
