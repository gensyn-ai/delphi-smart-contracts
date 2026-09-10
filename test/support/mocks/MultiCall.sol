// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract MultiCall {
    function multicall(address[] calldata targets, bytes[] calldata datas) external {
        require(targets.length == datas.length, "array lengths should match");

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success,) = targets[i].call(datas[i]);
            if (success) {
                continue;
            }

            // Bubble up revert
            assembly ("memory-safe") {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }
        }
    }
}
