// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IBaseTBContract
/// @notice Interface a Truebit consumer contract must implement to receive WatchTower callbacks.
/// @dev Mirrors the surface of Truebit's BaseTBContract without inheriting it (see TruebitOracleRelayer).
interface IBaseTBContract {
    /// @notice Returns the task source code. Unused for registered (FUNCTION / API) tasks.
    function getTaskSource() external view returns (string memory);

    /// @notice Called by the WatchTower with the result of a previously requested execution.
    /// @param resultData The raw result bytes returned by the WatchTower.
    /// @param transcripts The WatchTower execution transcripts.
    /// @param wtExecutionId The WatchTower execution id the callback corresponds to.
    /// @param status The raw execution status (see DOTypes.ExecutionStatus).
    /// @param callbackMessageDetails Additional callback details (unused by the relayer).
    function callbackTask(
        bytes calldata resultData,
        string[] memory transcripts,
        uint256 wtExecutionId,
        uint8 status,
        string memory callbackMessageDetails
    ) external;
}
