// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDynamicParimutuelMarketTypes} from "./IDynamicParimutuelMarketTypes.sol";
import {IDynamicParimutuelMathErrors} from "src/delphi/dynamicParimutuel/math/IDynamicParimutuelMathErrors.sol";

interface IDynamicParimutuelMarketErrors is IDynamicParimutuelMarketTypes, IDynamicParimutuelMathErrors {
    error ArrayLengthMismatch(uint256 ownersLength, uint256 indicesLength);
    error CallerNotGateway(address caller);
    error EmptyOutcomeIndices();
    error EmptyUri();
    error EmptyUriContentHash();
    error InitialLiquidityTooHigh(uint256 provided, uint256 maximum);
    error InitialLiquidityTooLow(uint256 provided, uint256 minimum);
    error InvalidBuy();
    error InvalidSell();
    error KTooHigh(uint256 provided, uint256 maximum);
    error KTooLow(uint256 provided, uint256 minimum);
    error MarketNotProperlyFunded(uint256 balance, uint256 required);
    error OutcomeCountTooHigh(uint256 provided, uint256 maximum);
    error OutcomeCountTooLow(uint256 provided, uint256 minimum);
    error RedeemZeroShares();
    error RedeemZeroTokensOut();
    error SettlementDeadlineBeforeTradingDeadline(uint256 settlement, uint256 trading);
    error SettlementWindowTooLong(uint256 provided, uint256 maximum);
    error SettlementWindowTooShort(uint256 provided, uint256 minimum);
    error TokenDecimalsTooHigh(uint8 decimals);
    error TokenDecimalsTooLow(uint8 decimals);
    error TradingDeadlineNotInFuture(uint256 deadline, uint256 currentTimestamp);
    error TradingFeeTooHigh(uint256 provided, uint256 maximum);
    error TradingFeeTooLow(uint256 provided, uint256 minimum);
    error TradingFeesRecipientPctTooHigh(uint256 provided, uint256 maximum);
    error TradingFeesRecipientPctTooLow(uint256 provided, uint256 minimum);
    error TradingWindowTooLong(uint256 provided, uint256 maximum);
    error TradingWindowTooShort(uint256 provided, uint256 minimum);
    error WinningOutcomeOutOfBounds(uint256 provided, uint256 outcomeCount);
    error WrongMarketStatus(MarketStatus current, MarketStatus required);
    error ZeroGatewayAddress();
    error ZeroMarketCreatorAddress();
    error ZeroSharesPerOutcome();
    error ZeroTokenAddress();
    error ZeroTradingFeesRecipientAddress();
    error GrossTokensOutExceedMarketPool(uint256 grossTokensOut, uint256 marketPool);
    error CallerNotMarketCreator(address caller, address marketCreator);
    error MarketCreationSharesAlreadyLiquidated();
}
