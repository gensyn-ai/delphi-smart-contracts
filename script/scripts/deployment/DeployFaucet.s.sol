// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";
import {GensynFaucetDeployer} from "script/utils/deployer/GensynFaucetDeployer.sol";

// Types
import {GensynFaucetUpgradeable} from "src/token/GensynFaucetUpgradeable.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract DeployFaucet_Script is GensynFaucetDeployer, BaseScript {
    // Libraries
    using stdJson for string;

    function run()
        external
        broadcast
        returns (GensynFaucetUpgradeable faucetProxy, GensynFaucetUpgradeable faucetImplementation)
    {
        // Read config
        string memory json = _getJson("script/input/deployment/DeployFaucet.json");

        address token = json.readAddress(".token");
        address admin = json.readAddress(".admin");
        address dripManager = json.readAddress(".dripManager");
        uint256 dripTime = json.readUint(".dripTime");
        uint256 dripAmount = json.readUint(".dripAmount");
        address implementation = json.readAddress(".implementation");

        // Deploy
        GensynFaucetConfig memory config = GensynFaucetConfig({dripTime: dripTime, dripAmount: dripAmount});
        (faucetProxy, faucetImplementation) =
            _deployGensynFaucetProxy(token, admin, dripManager, implementation, config);
    }
}
