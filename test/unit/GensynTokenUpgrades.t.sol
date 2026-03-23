// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseTest} from "test/utils/BaseTest.t.sol";
import {AllDeployer} from "script/utils/deployer/AllDeployer.sol";

// Contracts
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {GensynTokenV2} from "test/utils/mocks/GensynTokenV2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// Types
import {Addresses} from "script/utils/Addresses.sol";
import {Vm} from "forge-std/Vm.sol";

// Libraries
import {GnosisSafeTestUtils} from "test/utils/GnosisSafeTestUtils.sol";

contract GensynTokenUpgrades_Test is BaseTest, AllDeployer {
    // State Variables
    Vm.Wallet safeOwner1 = vm.createWallet("SafeOwner1");
    Vm.Wallet safeOwner2 = vm.createWallet("SafeOwner2");
    Addresses deployment;
    GensynTokenV2 newTokenImplementation;

    // Libraries
    using GnosisSafeTestUtils for Vm;

    modifier setUp(uint8 decimals) {
        address[] memory safeOwners = new address[](2);
        safeOwners[0] = safeOwner1.addr;
        safeOwners[1] = safeOwner2.addr;

        // Deploy
        deployment = _deployAll({
            deployer: address(this),
            addresses: deployment,
            config: DeployAllConfig({
                tokenTimelockSafeProxy: SafeProxyConfig({owners: safeOwners, threshold: 2}),
                delphiTimelockSafeProxy: SafeProxyConfig({owners: safeOwners, threshold: 2}),
                delphiSafeProxy: SafeProxyConfig({owners: safeOwners, threshold: 2}),
                tokenTimelock: TimelockConfig({minDelay: 7 days}),
                delphiTimelock: TimelockConfig({minDelay: 7 days}),
                gensynToken: GensynTokenConfig({
                    name: "Test Token",
                    symbol: "TEST",
                    initialSupply: 10_000_000_000e18, // 10 billion
                    decimals: _boundUint8(decimals, 6, 18)
                }),
                gensynFaucet: GensynFaucetConfig({dripTime: 1, dripAmount: 1})
            })
        });

        newTokenImplementation = new GensynTokenV2();

        _;
    }

    function test_NonAdmin_Reverts(uint8 decimals) external setUp(decimals) {
        address user = makeAddr("USER");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                deployment.gensynTokenProxy.DEFAULT_ADMIN_ROLE()
            )
        );
        _useNewSender(user);
        deployment.gensynTokenProxy.upgradeToAndCall(address(newTokenImplementation), "");
    }

    function test_Upgrade(uint8 decimals) external setUp(decimals) {
        bytes memory tokenUpgradeData =
            abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newTokenImplementation), ""));
        bytes memory timelockData = abi.encodeCall(
            TimelockController.schedule,
            (
                address(deployment.gensynTokenProxy), // target
                0, // value
                tokenUpgradeData, // data
                bytes32(0), // predecessor
                bytes32(0), // salt
                7 days //delay
            )
        );

        // Build safe owner private keys
        uint256[] memory safeOwners = new uint256[](2);
        safeOwners[0] = safeOwner1.privateKey;
        safeOwners[1] = safeOwner2.privateKey;

        // Schedule upgrade via timelock
        bool success = vm.buildJointSigFromPrivateKeysAndExecTransaction({
            safeProxy: deployment.tokenTimelockSafeProxy,
            to: address(deployment.tokenTimelock),
            data: timelockData,
            safeOwnerPrivateKeys: safeOwners
        });
        vm.assertTrue(success, "operation should have succeeed");

        skip(7 days);
        deployment.tokenTimelock
            .execute({
                target: address(deployment.gensynTokenProxy),
                value: 0,
                payload: tokenUpgradeData,
                predecessor: bytes32(0),
                salt: bytes32(0)
            });

        uint256 value = 0x1234;
        GensynTokenV2(address(deployment.gensynTokenProxy)).setFoo(value);
        vm.assertEq(GensynTokenV2(address(deployment.gensynTokenProxy)).foo(), value, "should set foo");
    }
}
