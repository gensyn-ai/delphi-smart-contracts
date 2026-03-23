// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    // Chain IDs
    uint256 constant GENSYN_TESTNET_CHAIN_ID = 685_685;
    uint256 constant GENSYN_MAINNET_CHAIN_ID = 685_689;
    uint256 constant ANVIL_CHAIN_ID = 31_337;

    // Modifiers
    modifier broadcastPk(uint256 privateKey) {
        require(block.chainid != GENSYN_MAINNET_CHAIN_ID, "Cannot run on mainnet");
        vm.startBroadcast(privateKey);
        _;
        vm.stopBroadcast();
    }

    modifier broadcast() {
        require(block.chainid != GENSYN_MAINNET_CHAIN_ID, "Cannot run on mainnet");
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    function _getJson(string memory path_) internal view returns (string memory json) {
        // Get root
        string memory root = vm.projectRoot();

        // Get path
        string memory path = string.concat(root, "/", path_);

        // Read and return file
        // forge-lint: disable-next-line(unsafe-cheatcode)
        json = vm.readFile(path);
    }
}
