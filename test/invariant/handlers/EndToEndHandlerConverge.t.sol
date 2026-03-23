// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {EndToEndHandler} from "./EndToEndHandler.t.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract EndToEndHandler_Converge is EndToEndHandler {
    // ========== STATE VARIABLES ==========
    EnumerableSet.UintSet private _losingOutcomeIndices; // with or without external shares (doesn't matter for buyExactOut)

    // ========== LIBRARIES ==========
    using EnumerableSet for EnumerableSet.UintSet;
    using Math for uint256;

    // ========== CONSTRUCTOR ==========
    constructor(uint256 minTradesPerMarket, uint256 maxTradesPerMarket, uint256 maxTraderCount)
        EndToEndHandler(minTradesPerMarket, maxTradesPerMarket, maxTraderCount)
    {}

    function _deployMarket(DeployMarketArgs memory args) internal override {
        // Deploy market
        // Note: sets marketProxyConfig and winningOutcomeIdx
        super._deployMarket(args);

        // For each outcome
        for (uint256 i = 0; i < _marketProxyConfig.outcomeCount; i++) {
            // If outcome is losing outcome
            if (i != winningOutcomeIdx) {
                // Add losing outcome to losing outcomes
                _losingOutcomeIndices.add(i);
            }
        }
    }

    function _getOutcomeForBuyExactOut(uint256 outcomeIdxSeed) internal view override returns (uint256) {
        // If winner is selected (with increasing probability as trade count increases)
        if (_winnerSelectedIncreasing(outcomeIdxSeed)) {
            // Return winner
            return winningOutcomeIdx;

            // If winner is not selected
        } else {
            // Return random losing outcome (with external shares or not, doesn't matter for buyExactOut)
            return _randomUintArrayElement(_losingOutcomeIndices.values(), outcomeIdxSeed);
        }
    }

    /*
     * Question:
     * Should selling the winning outcome become more likely with time? Or less? Or stay random?
     * I think the chance of selling losing outcomes should definitely increase over time.
     * Hence, I think the chance of selling the winning outcome should decrease over time.
     */
    function _getOutcomeForSellExactIn(uint256 outcomeIdxSeed) internal view override returns (uint256) {
        // If there are no losing outcomes with external shares
        // Note: This is needed, as we could enter sell even if there are no losing outcomes with external shares (if the winning outcome has external shares)
        if (_losingOutcomeIndicesWithExternalShares.length() == 0) {
            // Ensure winning outcome has external shares
            assertGt(
                _externalSupply(winningOutcomeIdx),
                0,
                "_getOutcomeForSellExactIn: neither winning outcome nor losing outcomes have external shares"
            );

            // Return winning outcome
            return winningOutcomeIdx;

            // If there are losing outcomes with external shares
        } else {
            // If winner is selected (with decreasing probability as trade count increases)
            if (_winnerSelectedDecreasing(outcomeIdxSeed)) {
                // If external shares exist for winning outcome
                if (_externalSupply(winningOutcomeIdx) > 0) {
                    // Return winning outcome
                    return winningOutcomeIdx;
                }
            }

            // Return random losing outcome with external shares
            return _randomUintArrayElement(_losingOutcomeIndicesWithExternalShares.values(), outcomeIdxSeed);
        }
    }

    // ========== PRIVATE ==========
    function _winnerSelectedIncreasing(uint256 randomness) private view returns (bool) {
        return bound(randomness, 0, 100) <= _tradeCountPct();
    }

    function _winnerSelectedDecreasing(uint256 randomness) private view returns (bool) {
        return bound(randomness, 0, 100) > _tradeCountPct();
    }

    function _tradeCountPct() private view returns (uint256) {
        return tradeCount.mulDiv(100, MAX_TRADES_PER_MARKET);
    }
}
