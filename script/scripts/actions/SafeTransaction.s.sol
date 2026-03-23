// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";

// Contracts
import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeUtils} from "script/utils/GnosisSafeUtils.sol";
import {GnosisSafeScriptUtils} from "script/utils/GnosisSafeScriptUtils.sol";
// import {IDelphi} from "src/delphi/delphi/Delphi.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract SafeTransactions_Script is BaseScript {
    // Libraries
    using stdJson for string;
    using GnosisSafeUtils for GnosisSafeL2;
    using GnosisSafeScriptUtils for string;

    function execTransaction() external broadcast {
        string memory json = _getJson();

        // Get safe proxy from json
        GnosisSafeL2 safeProxy = _getSafeProxyFromJson(json);

        bool success = safeProxy.buildJointSigAndExecTransaction({
            to: _getToFromJson(json), data: _getDataFromJson(json), sigs: json._getSigsFromJson(".signatures")
        });

        // Ensure success
        require(success, "Safe transaction failed");
    }

    // ===== INTERNAL UTILS =====

    function _getSafeProxyFromJson(string memory json) internal pure returns (GnosisSafeL2) {
        return GnosisSafeL2(payable(json.readAddress(".safeProxy")));
    }

    // function _getDelphiProxyFromJson(string memory json) internal pure returns (IDelphi) {
    //     return IDelphi(json.readAddress(".delphiProxy"));
    // }

    function _getToFromJson(string memory json) internal pure returns (address) {
        return json.readAddress(".to");
    }

    function _getDataFromJson(string memory json) internal pure returns (bytes memory) {
        return json.readBytes(".data");
    }

    function _getJson() internal view virtual returns (string memory json) {
        return _getJson("/script/input/actions/SafeTransaction.json");
    }
}
