// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDynamicParimutuelMathErrors} from "src/delphi/dynamicParimutuel/math/IDynamicParimutuelMathErrors.sol";

interface IDynamicParimutuelGatewayErrors is IDynamicParimutuelMathErrors {
    error GrossTokensOutNotPositive();
    error MarketNotOpen();
    error OutcomeSupplyBelowMinDelta(uint256 newSupply, uint256 minDelta);
    error SellOverlap();
    error SharesInBelowMinDelta(uint256 sharesIn, uint256 minDelta);
    error SharesOutBelowMinDelta(uint256 sharesOut, uint256 minDelta);
    error TokensInBelowMin(uint256 tokensIn, uint256 minTokensIn);
    error TokensInExceedsMax(uint256 tokensIn, uint256 maxTokensIn);
    error TokensOutBelowMin(uint256 tokensOut, uint256 minTokensOut);
    error ZeroNetTokensIn();
    error InitializerNotDeployer(address initializer, address deployer);
    error DelphiFactoryIsZeroAddress();
    error DelphiFactoryIsNotContract(address delphiFactory);
    error GatewayNotInitialized();
    error MarketProxyNotDeployedByFactory(address marketProxy);
    error OutcomeNewExpInputTooLarge(uint256 outcomeNewExpInput, uint256 maxExpInput);
}
