// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";
import {TimelockDeployer} from "script/utils/deployer/TimelockDeployer.sol";

// Types
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

// Logging
import {console2} from "forge-std/console2.sol";

contract DeployTimelock_Script is TimelockDeployer, BaseScript {
    using stdJson for string;

    function run() external broadcast returns (TimelockController timelock) {
        // Get config json
        string memory json = _getJson("script/input/deployment/DeployTimelock.json");

        // Get proposer (the sole address allowed to schedule operations)
        address proposer = json.readAddress(".proposer");

        // Get timelock config
        TimelockConfig memory config = _getTimelockConfigFromJson(json, ".timelock");

        // Deploy timelock (open executor, no admin)
        timelock = _deployTimelock(proposer, config);

        // Log
        console2.log("TimelockController deployed at:", address(timelock));
    }
}
