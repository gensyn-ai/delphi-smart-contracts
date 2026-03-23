// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseTest} from "test/utils/BaseTest.t.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {GensynFaucetUpgradeable} from "src/token/GensynFaucetUpgradeable.sol";
import {GensynFaucetDeployer} from "script/utils/deployer/GensynFaucetDeployer.sol";

contract GensynFaucetUpgrades_Test is BaseTest, GensynFaucetDeployer {
    address token = makeAddr("token");
    GensynFaucetUpgradeable gensynFaucet;

    uint256 dripTime = 24 hours;
    uint256 dripAmount = ONE;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    address owner = makeAddr("owner");

    function setUp() external {
        (gensynFaucet,) = _deployGensynFaucetProxy(
            token, owner, owner, address(0), GensynFaucetConfig({dripTime: dripTime, dripAmount: dripAmount})
        );

        vm.warp(48 hours);
    }

    function test_Unauthorized_Reverts() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user1, gensynFaucet.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.startPrank(user1, user1);
        gensynFaucet.upgradeToAndCall(user2, "");
    }

    function test_Upgrade() external {
        address implementation2 = address(new GensynFaucetUpgradeable(user2));

        _useNewSender(owner);
        gensynFaucet.upgradeToAndCall(implementation2, "");

        vm.assertEq(address(gensynFaucet.GENSYN_TOKEN()), user2);
    }
}
