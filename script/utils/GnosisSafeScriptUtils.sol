// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

library GnosisSafeScriptUtils {
    // Libraries
    using stdJson for string;

    function _getSigsFromJson(string memory json, string memory key) internal pure returns (bytes[] memory sigs) {
        sigs = abi.decode(json.parseRaw(key), (bytes[]));
    }
}
