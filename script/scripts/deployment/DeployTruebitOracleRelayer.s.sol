// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";
import {TruebitOracleRelayerDeployer} from "script/utils/deployer/TruebitOracleRelayerDeployer.sol";

// Types
import {TruebitOracleRelayer} from "src/oracle/TruebitOracleRelayer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

// Logging
import {console2} from "forge-std/console2.sol";

contract DeployTruebitOracleRelayer_Script is TruebitOracleRelayerDeployer, BaseScript {
    using stdJson for string;

    function run() external broadcast returns (TruebitOracleRelayer proxy, TruebitOracleRelayer implementation) {
        // Get config json
        string memory json = _getJson("script/input/deployment/DeployTruebitOracleRelayer.json");

        // Get gateway
        ILmsrGateway gateway = ILmsrGateway(json.readAddress(".gateway"));

        // Deploy truebit oracle relayer (proxy and implementation)
        (proxy, implementation) = _deployTruebitOracleRelayerProxy({
            watchTower: json.readAddress(".watchTower"),
            gateway: gateway,
            executionTimeout: json.readUint(".executionTimeout"),
            async_: json.readBool(".async"),
            implementation: json.readAddress(".implementation"),
            params: TruebitOracleRelayer.InitParams({
                owner: json.readAddress(".owner"), oracleFeeRecipient: json.readAddress(".oracleFeeRecipient")
            })
        });

        // Get msg.sender
        (, address msgSender,) = vm.readCallers();

        // If msg.sender is the gateway's owner
        if (msgSender == Ownable(address(gateway)).owner()) {
            // Log
            console2.log("msg.sender == gateway's owner. calling setOracleRelayer...");

            // Effects: Set gateway's oracle relayer
            gateway.setOracleRelayer(address(proxy));
        } else {
            // Log
            console2.log("msg.sender != gateway's owner. skipped setOracleRelayer");
        }
    }
}
