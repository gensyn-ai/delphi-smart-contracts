// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IDelphiFactoryErrors {
    error ImplementationNotAContract(address implementation);
    error ZeroImplementationAddress();
    error ZeroFeeRecipientAddress();
    error MarketCreationFeeTooLow(uint256 provided, uint256 minimum);
    error MarketCreationFeeTooHigh(uint256 provided, uint256 maximum);
    error FirstIdxExceedsLastIdx(uint256 firstIdx, uint256 lastIdx);
    error LastIdxOutOfBounds(uint256 lastIdx, uint256 marketCount);
}
