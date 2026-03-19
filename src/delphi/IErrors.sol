// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDynamicParimutuelMathErrors} from "src/delphi/dynamicParimutuel/math/IDynamicParimutuelMathErrors.sol";
import {
    IDynamicParimutuelGatewayErrors
} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGatewayErrors.sol";
import {
    IDynamicParimutuelMarketErrors
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketErrors.sol";
import {IDelphiFactoryErrors} from "src/delphi/factory/IDelphiFactoryErrors.sol";

interface IErrors is
    IDynamicParimutuelMathErrors,
    IDynamicParimutuelGatewayErrors,
    IDynamicParimutuelMarketErrors,
    IDelphiFactoryErrors
{}
