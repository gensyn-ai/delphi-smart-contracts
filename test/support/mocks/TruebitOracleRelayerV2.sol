// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {TruebitOracleRelayer} from "src/oracle/TruebitOracleRelayer.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";

/// @dev Test-only V2 implementation. Appends a storage var via its own ERC-7201 namespace to prove the
///      relayer's storage layout is upgrade-safe (append-only). Not part of production.
contract TruebitOracleRelayerV2 is TruebitOracleRelayer {
    /// @custom:storage-location erc7201:TruebitOracleRelayerV2
    struct V2Storage {
        uint256 appendedValue;
    }

    // ERC7201(TruebitOracleRelayerV2)
    bytes32 private constant _V2_SLOT = 0x2fb960e5f86e21ba725446a881d7241ab3904f07a845ff87938ce17e41c8b400;

    constructor(address watchTowerAddress, ILmsrGateway gateway_, uint256 executionTimeout_, bool async_)
        TruebitOracleRelayer(watchTowerAddress, gateway_, executionTimeout_, async_)
    {}

    function setAppendedValue(uint256 v) external {
        _v2().appendedValue = v;
    }

    function appendedValue() external view returns (uint256) {
        return _v2().appendedValue;
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function _v2() private pure returns (V2Storage storage $) {
        assembly ("memory-safe") {
            $.slot := _V2_SLOT
        }
    }
}
