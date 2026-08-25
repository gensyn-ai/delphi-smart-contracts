// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";
import {TruebitOracleRelayerDeployer} from "script/utils/deployer/TruebitOracleRelayerDeployer.sol";

// Types
import {TruebitOracleRelayer} from "src/delphi/oracle/TruebitOracleRelayer.sol";

// Interfaces
import {IDynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGateway.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract DeployTruebitOracleRelayer_Script is TruebitOracleRelayerDeployer, BaseScript {
    using stdJson for string;

    function run() external broadcast returns (TruebitOracleRelayer proxy, TruebitOracleRelayer implementation) {
        // Read config
        string memory json = _getJson("script/input/deployment/DeployTruebitOracleRelayer.json");

        address watchTower = json.readAddress(".watchTower");
        address impl = json.readAddress(".implementation");
        IDynamicParimutuelGateway gateway = IDynamicParimutuelGateway(json.readAddress(".gateway"));
        uint256 executionTimeout = json.readUint(".executionTimeout");
        bool async_ = json.readBool(".async");

        TruebitOracleRelayer.InitParams memory params = TruebitOracleRelayer.InitParams({
            owner: json.readAddress(".owner"), oracleFeeRecipient: json.readAddress(".oracleFeeRecipient")
        });

        (proxy, implementation) =
            _deployTruebitOracleRelayerProxy(watchTower, gateway, executionTimeout, async_, impl, params);
    }
}
