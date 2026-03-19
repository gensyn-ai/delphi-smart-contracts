// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";

// Types
import {Vm} from "forge-std/Vm.sol";

// Libraries
import {GnosisSafeUtils} from "script/utils/GnosisSafeUtils.sol";

library GnosisSafeTestUtils {
    // Libraries
    using GnosisSafeUtils for GnosisSafeL2;

    function buildJointSigFromPrivateKeysAndExecTransaction(
        Vm vm,
        GnosisSafeL2 safeProxy,
        address to,
        bytes memory data,
        uint256[] memory safeOwnerPrivateKeys
    ) internal returns (bool) {
        // get transaction hash
        bytes32 txHash = safeProxy._getTransactionHash({to: to, data: data});

        // Ensure enough signatures were provided
        require(safeOwnerPrivateKeys.length >= safeProxy.getThreshold(), "Not enough signatures provided");

        // Build sigs array
        bytes[] memory sigs = new bytes[](safeOwnerPrivateKeys.length);
        for (uint256 i = 0; i < safeOwnerPrivateKeys.length; i++) {
            // Create sig
            sigs[i] = _sign(vm, safeOwnerPrivateKeys[i], txHash);
        }

        // Build joint signature and execute transaction
        return safeProxy.buildJointSigAndExecTransaction({to: to, data: data, sigs: sigs});
    }

    function _sign(Vm vm, uint256 pk, bytes32 opHash) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, opHash);
        return abi.encodePacked(r, s, v);
    }
}
