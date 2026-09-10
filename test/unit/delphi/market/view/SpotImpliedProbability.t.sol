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

contract LmsrMarket_SpotImpliedProbability_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Immutables
    address immutable ORACLE_FEE_RECIPIENT = makeAddr("ORACLE_FEE_RECIPIENT");
    address immutable BUYER = makeAddr("BUYER");

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

    /// @dev Deploys a bounded market and buys a fuzz-bounded position so outcome probabilities are not uniform.
    function _deployAndBuy(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 boughtOutcomeIdx,
        uint256 sharesOut
    ) internal returns (uint256) {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound bought outcome idx and shares out
        boughtOutcomeIdx = bound(boughtOutcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: boughtOutcomeIdx})
        );

        // Buy shares so probabilities are not uniform
        _buy({buyer: BUYER, outcomeIdx: boughtOutcomeIdx, sharesOut: sharesOut});

        return boughtOutcomeIdx;
    }

    // Tests

    function testFuzz_SpotImpliedProbability_OutcomeIsOutOfBounds_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 outcomeIdx
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

        // Spot implied probability
        marketProxy.spotImpliedProbability(outcomeIdx);
    }

    function testFuzz_SpotImpliedProbability_Settled_ReturnsClaimValues(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 boughtOutcomeIdx,
        uint256 sharesOut,
        uint256 winningOutcomeIdx
    ) external {
        // Deploy and buy (so probabilities are not uniform)
        _deployAndBuy(tokenDecimals, delphiConfig, marketConfig, initialDeposit, boughtOutcomeIdx, sharesOut);

        // Bound winning outcome idx
        uint256 outcomeCount = marketProxy.getMarket().config.outcomeCount;
        winningOutcomeIdx = bound(winningOutcomeIdx, 0, outcomeCount - 1);

        // Advance time (so that market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Settle market (so that market is SETTLED)
        _useNewSender(address(deployment.gateway));
        marketProxy.settleMarket({winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: ORACLE_FEE_RECIPIENT});

        // The winning outcome has probability one (1e18); losing outcomes have probability zero
        uint256[] memory outcomeIndices = new uint256[](outcomeCount);
        for (uint256 outcomeIdx = 0; outcomeIdx < outcomeCount; outcomeIdx++) {
            outcomeIndices[outcomeIdx] = outcomeIdx;
            if (outcomeIdx == winningOutcomeIdx) {
                assertEq(marketProxy.spotImpliedProbability(outcomeIdx), 1e18, "winning probability != 1e18");
            } else {
                assertEq(marketProxy.spotImpliedProbability(outcomeIdx), 0, "losing probability != 0");
            }
        }

        // The batch variant must match the single-value variant
        uint256[] memory impliedProbabilities = marketProxy.spotImpliedProbabilities(outcomeIndices);
        for (uint256 outcomeIdx = 0; outcomeIdx < outcomeCount; outcomeIdx++) {
            assertEq(
                impliedProbabilities[outcomeIdx],
                marketProxy.spotImpliedProbability(outcomeIdx),
                "batch probability != single probability"
            );
        }
    }

    function testFuzz_SpotImpliedProbability_Failed_ReturnsFrozenLmsrProbabilities(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 boughtOutcomeIdx,
        uint256 sharesOut
    ) external {
        // Deploy and buy (so probabilities are not uniform)
        _deployAndBuy(tokenDecimals, delphiConfig, marketConfig, initialDeposit, boughtOutcomeIdx, sharesOut);

        // Advance time (so that market is AWAITING_SETTLEMENT)
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Record the frozen LMSR closing probabilities
        uint256 outcomeCount = marketProxy.getMarket().config.outcomeCount;
        uint256[] memory closingProbabilities = new uint256[](outcomeCount);
        for (uint256 outcomeIdx = 0; outcomeIdx < outcomeCount; outcomeIdx++) {
            closingProbabilities[outcomeIdx] = marketProxy.spotImpliedProbability(outcomeIdx);
        }

        // Fail market (so that market is FAILED)
        _useNewSender(address(deployment.gateway));
        marketProxy.failMarket();
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.FAILED), "market status != FAILED"
        );

        // FAILED markets keep reporting the frozen LMSR closing probabilities (used by liquidation)
        for (uint256 outcomeIdx = 0; outcomeIdx < outcomeCount; outcomeIdx++) {
            assertEq(
                marketProxy.spotImpliedProbability(outcomeIdx),
                closingProbabilities[outcomeIdx],
                "failed probability != closing probability"
            );
        }
    }
}
