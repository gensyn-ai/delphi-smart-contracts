// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseTest} from "test/utils/BaseTest.t.sol";

// Contract
import {TestToken} from "src/token/TestToken.sol";
import {GensynFaucetUpgradeable} from "src/token/GensynFaucetUpgradeable.sol";
import {Addresses} from "script/utils/Addresses.sol";
import {TimelockDeployer} from "script/utils/deployer/TimelockDeployer.sol";
import {GensynTokenDeployer} from "script/utils/deployer/GensynTokenDeployer.sol";
import {GensynFaucetDeployer} from "script/utils/deployer/GensynFaucetDeployer.sol";
import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";

contract GensynFaucet_Test is BaseTest, TimelockDeployer, GensynTokenDeployer, GensynFaucetDeployer {
    address immutable GENSYN_MULTSIG = makeAddr("GENSYN_MULTSIG");
    TestToken gensynToken;
    GensynFaucetUpgradeable gensynFaucet;

    uint256 dripTime = 24 hours;
    uint256 dripAmount = ONE;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    modifier setUp(uint8 decimals) {
        // Build empty addresses
        Addresses memory addresses;

        // Override safe addresses
        addresses.tokenTimelockSafeProxy = GnosisSafeL2(payable(GENSYN_MULTSIG));
        addresses.delphiTimelockSafeProxy = GnosisSafeL2(payable(GENSYN_MULTSIG));
        addresses.delphiSafeProxy = GnosisSafeL2(payable(GENSYN_MULTSIG));

        // Deploy timelock
        addresses = _deployTokenTimelock({
            addresses: addresses, proposer: GENSYN_MULTSIG, config: TimelockConfig({minDelay: 1})
        });

        addresses = _deployDelphiTimelock({
            addresses: addresses, proposer: GENSYN_MULTSIG, config: TimelockConfig({minDelay: 1})
        });

        // Deploy gensyn token
        addresses = _deployGensynTokenProxy({
            deployer: GENSYN_MULTSIG,
            addresses: addresses,
            config: GensynTokenConfig({
                name: "Test Token",
                symbol: "TEST",
                initialSupply: 1_000_000_000e18,
                decimals: _boundUint8(decimals, 6, 18)
            })
        });

        // Deploy gensyn faucet
        (addresses.gensynFaucetProxy, addresses.gensynFaucetImplementation) = _deployGensynFaucetProxy(
            address(addresses.gensynTokenProxy),
            address(addresses.delphiTimelock),
            address(addresses.delphiSafeProxy),
            address(addresses.gensynFaucetImplementation),
            GensynFaucetConfig({dripTime: dripTime, dripAmount: dripAmount})
        );

        // Set state variables
        gensynToken = addresses.gensynTokenProxy;
        gensynFaucet = addresses.gensynFaucetProxy;

        _useNewSender(GENSYN_MULTSIG);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        gensynToken.transfer(address(gensynFaucet), 25e18);
        vm.stopPrank();
        vm.warp(48 hours);

        _;
    }

    function test_RequestFaucet(uint8 decimals) external setUp(decimals) {
        vm.prank(user1, user1);
        gensynFaucet.requestToken();

        vm.assertEq(gensynToken.balanceOf(user1), dripAmount);
    }

    function testFuzz_RequestFaucet2Users(uint8 decimals) external setUp(decimals) {
        vm.prank(user1, user1);
        gensynFaucet.requestToken();

        vm.prank(user2, user2);
        gensynFaucet.requestToken();

        vm.assertEq(gensynToken.balanceOf(user1), dripAmount, "user1");
        vm.assertEq(gensynToken.balanceOf(user2), dripAmount, "user2");
    }

    function testFuzz_RequestFaucetTooOften_Revert(uint8 decimals) external setUp(decimals) {
        vm.startPrank(user1, user1);
        gensynFaucet.requestToken();

        vm.expectRevert(GensynFaucetUpgradeable.RequestTooOften.selector);
        gensynFaucet.requestToken();
    }

    function testFuzz_RequestFaucetTwice(uint8 decimals) external setUp(decimals) {
        vm.startPrank(user1, user1);
        gensynFaucet.requestToken();

        skip(48 hours);
        gensynFaucet.requestToken();

        vm.assertEq(gensynToken.balanceOf(user1), 2 * dripAmount);
    }
}
