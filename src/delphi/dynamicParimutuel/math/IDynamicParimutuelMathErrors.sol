// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IDynamicParimutuelMathErrors {
    error ZeroTokensIn();
    error ZeroSharesOut();
    error BuyTooSmall();
    error ZeroSharesIn();
    error SharesInExceedSupply(uint256 sharesIn, uint256 supply);
    error ZeroTokensOut();
    error SellTooSmall();
    error SqrtOverlap();
}
