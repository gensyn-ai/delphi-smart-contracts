// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {SafeTransactions_Script} from "./SafeTransaction.s.sol";

import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeUtils} from "script/utils/GnosisSafeUtils.sol";
import {GnosisSafeScriptUtils} from "script/utils/GnosisSafeScriptUtils.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract RemoveOwner_Script is SafeTransactions_Script {
    using GnosisSafeUtils for GnosisSafeL2;
    using GnosisSafeScriptUtils for string;
    using stdJson for string;

    function generateRemoveOwnerCalldata() public view returns (bytes memory) {
        // Get json
        string memory json = _getJson();

        // Get safe proxy from json
        GnosisSafeL2 safeProxy = _getSafeProxyFromJson(json);

        address removedOwner = json.readAddress(".removedOwner");
        uint256 newThreshold = json.readUint(".newThreshold");
        require(newThreshold > 1, "New Threshold should be bigger than one");

        return safeProxy.generateRemoveOwnerCalldata(removedOwner, newThreshold);
    }

    function safeBuildJointSigAndRemoveOwner() external broadcast {
        // Get json
        string memory json = _getJson();

        // Get safe proxy from json
        GnosisSafeL2 safeProxy = _getSafeProxyFromJson(json);

        // Build joint signature from json, and execute transaction
        bool success = safeProxy.buildJointSigAndExecTransaction({
            to: address(safeProxy), data: generateRemoveOwnerCalldata(), sigs: json._getSigsFromJson(".signatures")
        });

        // Ensure success
        require(success, "Remove owner transaction failed");
    }

    function _getJson() internal view override returns (string memory json) {
        return _getJson("/script/input/actions/SafeRemoveOwner.json");
    }
}
