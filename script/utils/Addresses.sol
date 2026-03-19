// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {TestToken} from "src/token/TestToken.sol";
import {GensynFaucetUpgradeable} from "src/token/GensynFaucetUpgradeable.sol";

struct Addresses {
    GnosisSafeL2 safeSingleton;
    GnosisSafeProxyFactory safeProxyFactory;
    TimelockController tokenTimelock;
    TimelockController delphiTimelock;
    GnosisSafeL2 tokenTimelockSafeProxy;
    GnosisSafeL2 delphiTimelockSafeProxy;
    GnosisSafeL2 delphiSafeProxy;
    TestToken gensynTokenImplementation;
    TestToken gensynTokenProxy;
    GensynFaucetUpgradeable gensynFaucetImplementation;
    GensynFaucetUpgradeable gensynFaucetProxy;
}
