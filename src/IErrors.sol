// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {IDelphiFactoryErrors} from "src/factory/IDelphiFactoryErrors.sol";

/// @title IErrors
/// @notice Aggregates every Delphi error interface into one, for consumers (tests, tooling)
///         that want a single import covering all custom errors.
interface IErrors is ILmsrMathErrors, ILmsrGatewayErrors, ILmsrMarketErrors, IDelphiFactoryErrors {}
