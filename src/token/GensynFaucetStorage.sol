// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

abstract contract GensynFaucetStorage {
    struct GensynFaucetData {
        uint256 dripTime;
        uint256 dripAmount;
        mapping(address user => uint256) lastRequested;
    }

    // ERC7201(GensynFaucetStorage)
    bytes32 private constant _GENSYN_FAUCET_STORAGE_SLOT =
        0x696e7c2be805bd38d798dce06fde7549fa38fe27645e2898d905edba72756600;

    function _getGensynFaucetStorage() internal pure returns (GensynFaucetData storage $) {
        assembly ("memory-safe") {
            $.slot := _GENSYN_FAUCET_STORAGE_SLOT
        }
    }
}
