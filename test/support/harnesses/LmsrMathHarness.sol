// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract LmsrMathHarness {
    function buyIsValid(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 tokenDecimalScaler
    ) external pure returns (uint256 newExpSum, bool valid) {
        (newExpSum, valid) = LmsrMath.buyIsValid(
            b, currentExpSum, modelCurrentSupply, tokensIn, sharesOut, tokenDecimalScaler
        );
    }

    function sellIsValid(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 sharesIn,
        uint256 tokensOut,
        uint256 tokenDecimalScaler
    ) external pure returns (uint256 newExpSum, bool valid) {
        (newExpSum, valid) = LmsrMath.sellIsValid(
            b, currentExpSum, modelCurrentSupply, sharesIn, tokensOut, tokenDecimalScaler
        );
    }

    function addFee(uint256 netAmount, uint256 tradingFee)
        external
        pure
        returns (uint256 grossAmount, uint256 feeAmount)
    {
        (grossAmount, feeAmount) = LmsrMath.addFee(netAmount, tradingFee);
    }

    function deductFee(uint256 grossAmount, uint256 tradingFee)
        external
        pure
        returns (uint256 netAmount, uint256 feeAmount)
    {
        (netAmount, feeAmount) = LmsrMath.deductFee(grossAmount, tradingFee);
    }

    function outcomeExp(uint256 b, uint256 modelCurrentSupply) external pure returns (uint256) {
        return LmsrMath.outcomeExp(b, modelCurrentSupply);
    }

    function spotPrice(uint256 b, uint256 outcomeSupply, uint256 marketExp, uint256 tokenDecimalScaler)
        external
        pure
        returns (uint256)
    {
        return LmsrMath.spotPrice(b, outcomeSupply, marketExp, tokenDecimalScaler);
    }

    function spotImpliedProbability(uint256 b, uint256 outcomeSupply, uint256 marketExp)
        external
        pure
        returns (uint256)
    {
        return LmsrMath.spotImpliedProbability(b, outcomeSupply, marketExp);
    }

    function maxLoss(uint256 b, uint256 modelCount, uint256 tokenDecimalScaler) external pure returns (uint256) {
        return LmsrMath.maxLoss(b, modelCount, tokenDecimalScaler);
    }

    function redeemerReward(uint256 winningSharesIn, uint256 tokenDecimalScaler) external pure returns (uint256) {
        return LmsrMath.redeemerReward(winningSharesIn, tokenDecimalScaler);
    }

    function liquidatorTotalReward(uint256 numeratorSum36, uint256 currentExpSum, uint256 tokenDecimalScaler)
        external
        pure
        returns (uint256)
    {
        return LmsrMath.liquidatorTotalReward(numeratorSum36, currentExpSum, tokenDecimalScaler);
    }

    function tradingFeesRecipientCut(uint256 tradingFees, uint256 tradingFeesRecipientPct)
        external
        pure
        returns (uint256)
    {
        return LmsrMath.tradingFeesRecipientCut(tradingFees, tradingFeesRecipientPct);
    }

    function getExpUpperBound(uint256 exp) external pure returns (uint256) {
        return LmsrMath.getExpUpperBound(exp);
    }

    function getExpLowerBound(uint256 exp) external pure returns (uint256) {
        return LmsrMath.getExpLowerBound(exp);
    }

    function computeLnUpperBound(uint256 lnInput) external pure returns (uint256) {
        return LmsrMath.computeLnUpperBound(lnInput);
    }

    function computeLnLowerBound(uint256 lnInput) external pure returns (uint256) {
        return LmsrMath.computeLnLowerBound(lnInput);
    }

    function computeExp(uint256 expInput) external pure returns (uint256) {
        // Note: Trick to calculate exp without having access to the private _computeExp function
        return LmsrMath.outcomeExp({b: 1e18, outcomeSupply: expInput});
    }

    function _computeLn(uint256 lnInput) external pure returns (uint256) {
        // Note: Trick to calculate ln without having access to the private _computeLn function
        return LmsrMath.computeLnUpperBound(lnInput) - LmsrMath._MAX_LN_ABS_ERROR;
    }
}
