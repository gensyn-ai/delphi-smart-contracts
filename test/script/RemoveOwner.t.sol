// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {SafeDeployer} from "script/utils/deployer/SafeDeployer.sol";
import {BaseTest} from "test/utils/BaseTest.t.sol";

// Types
import {Addresses} from "script/utils/Addresses.sol";

import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeUtils} from "script/utils/GnosisSafeUtils.sol";
import {GnosisSafeTestUtils} from "../utils/GnosisSafeTestUtils.sol";
import {Vm} from "forge-std/Vm.sol";

contract RemoveOwner_Test is SafeDeployer, BaseTest {
    using GnosisSafeUtils for GnosisSafeL2;
    using GnosisSafeTestUtils for Vm;

    uint256 ownerCount = 2;
    Vm.Wallet[] owners;
    GnosisSafeL2 safeProxy;

    function setUp() external {
        address[] memory addrs = new address[](2);
        for (uint256 i = 0; i < ownerCount; i++) {
            uint256 pk = vm.randomUint();
            Vm.Wallet memory wallet = vm.createWallet(pk);
            owners.push(wallet);
            addrs[i] = wallet.addr;
        }

        Addresses memory deployment;
        deployment = _deployDelphiSafeProxy(deployment, SafeProxyConfig({owners: addrs, threshold: ownerCount}));
        safeProxy = deployment.delphiSafeProxy;
    }

    function test_RemoveOwner() external {
        address removedOwner = owners[0].addr;
        uint256 newThreshold = 1;

        uint256[] memory pks = new uint256[](ownerCount);
        for (uint256 i = 0; i < ownerCount; i++) {
            pks[i] = owners[i].privateKey;
        }

        bool success = vm.buildJointSigFromPrivateKeysAndExecTransaction({
            safeProxy: safeProxy,
            to: address(safeProxy),
            data: safeProxy.generateRemoveOwnerCalldata(removedOwner, newThreshold),
            safeOwnerPrivateKeys: pks
        });

        vm.assertTrue(success, "operation not sucessful");
        vm.assertFalse(safeProxy.isOwner(removedOwner), "Should not longer be owner");
        vm.assertEq(safeProxy.getThreshold(), 1, "New threshold should be one");
    }
}
