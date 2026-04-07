// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LogExpMath} from "lib/balancer-v3-monorepo/pkg/solidity-utils/contracts/math/LogExpMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title DelphiMath
/// @notice Math helpers for LMSR conservative exp/ln calculations.
/// @dev Wraps Balancer's {LogExpMath} fixed-point implementation and provides
///      upper/lower-bound helpers to safely round quotes.
library LmsrMath {
    /// @notice Thrown when an exp input exceeds MAX_EXP_INPUT.
    error ExpInputTooBig();

    /// @notice Maximum input accepted by _computeExp (1e18 fixed-point).
    uint256 public constant MAX_EXP_INPUT = 30e18;

    /// @dev Conservative relative error for exp calculations.
    uint256 internal constant _MAX_EXP_REL_ERROR = 0.000_1e18; // 0.01%

    /// @dev Conservative absolute error for ln calculations.
    uint256 internal constant _MAX_LN_ABS_ERROR = 100;

    /// @dev Fixed-point scalar (1e18).
    uint256 internal constant _ONE = 1e18;

    // Libraries
    using LogExpMath for int256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;

    /// @dev Returns a conservative lower bound for a precomputed exp.
    /// @param exp The precomputed exp to adjust (1e18 fixed-point).
    /// @return Lower bound according to _MAX_EXP_REL_ERROR.
    function _getExpLowerBound(uint256 exp) internal pure returns (uint256) {
        return exp - exp.mulDiv(_MAX_EXP_REL_ERROR, _ONE, Math.Rounding.Ceil);
    }

    /// @dev Returns a conservative upper bound for a precomputed exp.
    /// @param exp The precomputed exp to adjust (1e18 fixed-point).
    /// @return Upper bound according to _MAX_EXP_REL_ERROR.
    function _getExpUpperBound(uint256 exp) internal pure returns (uint256) {
        return exp + exp.mulDiv(_MAX_EXP_REL_ERROR, _ONE, Math.Rounding.Ceil);
    }

    /// @dev Computes exp(x) for 1e18 fixed-point inputs.
    /// @dev Internal, as it influences future trades (and therefore should callable directly)
    /// @param expInput Exponent input (1e18 fixed-point).
    /// @return exp(expInput) in 1e18 fixed-point.
    /// @custom:reverts ExpInputTooBig If expInput > MAX_EXP_INPUT.
    function _computeExp(uint256 expInput) internal pure returns (uint256) {
        require(expInput <= MAX_EXP_INPUT, ExpInputTooBig());
        return expInput.toInt256().exp().toUint256();
    }

    /// @dev Computes ln(x), and adjusts it to a conservative lower bound.
    /// @param lnInput Natural log input (1e18 fixed-point, must be >= 1e18).
    /// @return Lower bound according to _MAX_LN_REL_ERROR.
    function _computeLnLowerBound(uint256 lnInput) internal pure returns (uint256) {
        uint256 ln = _computeLn(lnInput);
        return ln - _MAX_LN_ABS_ERROR;
    }

    /// @dev Computes ln(x), and adjusts it to a conservative upper bound.
    /// @param lnInput Natural log input (1e18 fixed-point, must be >= 1e18).
    /// @return Upper bound according to _MAX_LN_REL_ERROR.
    function _computeLnUpperBound(uint256 lnInput) internal pure returns (uint256) {
        uint256 ln = _computeLn(lnInput);
        return ln + _MAX_LN_ABS_ERROR;
    }

    /// @dev Computes ln(x) using Balancer's fixed-point math.
    /// @dev Private, as its only used for quote calculations (and therefore should only be callable via "bounds" functions)
    /// @param lnInput Natural log input (1e18 fixed-point, must be > 1e18).
    /// @return ln(lnInput) in 1e18 fixed-point.
    function _computeLn(uint256 lnInput) private pure returns (uint256) {
        require(lnInput > _ONE, "ln input not > 1e18");
        return lnInput.toInt256().ln().toUint256();
    }
}
