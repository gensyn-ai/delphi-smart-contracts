// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract BaseTest is Test {
    // Public constants
    uint256 public constant ONE = 1e18;

    // Private constants
    uint256 private constant _MIN_PK = 1;
    uint256 private constant _SECP_256_K1_CURVE_ORDER =
        115792089237316195423570985008687907852837564279074904382605163141518161494337;
    uint256 private constant _MAX_PK = _SECP_256_K1_CURVE_ORDER - 1;

    using SafeCast for uint256;

    function _useNewSender(address sender) internal {
        vm.stopPrank();
        vm.startPrank(sender);
    }

    function _boundUint8(uint8 value, uint8 min, uint8 max) internal pure returns (uint8) {
        return bound(value, uint256(min), uint256(max)).toUint8();
    }

    function _handleCatch(bytes memory err, bytes4[] memory allowedErrorSelectors) internal pure returns (bytes4) {
        // Get selector
        bytes4 errorSelector = _getErrorSelector(err);

        // If error is allowed
        for (uint256 i; i < allowedErrorSelectors.length; i++) {
            if (errorSelector == allowedErrorSelectors[i]) {
                // Return
                // Note: vm.assume(false) discards the runs, and therefore all the calls made in it
                // Note: But we don't want to discard the rest of the calls, so we just return here
                // Note: We can return here, because this function is called inside a catch block
                return errorSelector;
            }
        }

        _bubbleUpError(err);
    }

    function _handleCatch(bytes memory err, bytes4 allowedErrorSelector) internal pure {
        bytes4 errorSelector = _getErrorSelector(err);
        if (errorSelector != allowedErrorSelector) {
            _bubbleUpError(err);
        }
    }

    function _getErrorSelector(bytes memory err) internal pure returns (bytes4 errorSelector) {
        assembly ("memory-safe") { errorSelector := mload(add(err, 0x20)) }
    }

    function _bubbleUpError(bytes memory err) internal pure {
        assembly ("memory-safe") {
            revert(add(err, 0x20), mload(err))
        }
    }

    function _randomAddressFromPk(uint256 pkSeed, uint256 minPk, uint256 maxPk) internal pure returns (address) {
        require(minPk >= _MIN_PK, "minPk not >= MIN_PK");
        require(maxPk <= _MAX_PK, "maxPk not <= MAX_PK");
        return vm.addr(bound(pkSeed, minPk, maxPk));
    }
}
