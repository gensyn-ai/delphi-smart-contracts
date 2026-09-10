// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IOracle
/// @notice Minimal interface the gateway uses to request market resolution from an oracle relayer.
interface IOracle {
    /// @notice Requests resolution of a market. Called by the gateway after it locks settlement.
    /// @dev Implementations must restrict this to the gateway and eventually call back
    ///      `settleMarket` or `failMarket` on the gateway.
    /// @param marketProxy The market proxy to resolve.
    function resolveMarket(address marketProxy) external;
}
