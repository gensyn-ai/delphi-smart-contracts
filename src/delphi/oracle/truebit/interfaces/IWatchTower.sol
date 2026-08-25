// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {DOTypes} from "../abstract/Types.sol";

/**
 * @title IWatchTower
 * @notice Interface for the WatchTower oracle system
 * @dev Contains all events, errors, and function signatures
 */
interface IWatchTower {
    // ========== EVENTS ==========

    /// @notice Emitted when a new execution request is made
    event TaskRequested(
        address indexed userContract,
        // forge-lint: disable-next-line(mixed-case-variable)
        address indexed userEOA,
        string methodSignature,
        bytes input,
        bytes32 codeHash,
        DOTypes.ExecutionType executionType,
        uint256 requestId
    );

    /// @notice Emitted when an address is added to the blacklist
    event AddressBlacklisted(address indexed blacklistedAddress);

    /// @notice Emitted when an address is removed from the blacklist
    event AddressRemovedFromBlacklist(address indexed removedAddress);

    /// @notice Emitted when a request is fulfilled
    event RequestFulfilled(uint256 indexed requestId, address indexed requester, uint8 status);

    /// @notice Emitted when a callback fails
    event CallbackFailed(uint256 indexed requestId, address indexed requester, string reason);

    // ========== ERRORS ==========
    /// @notice Thrown when an address is not blacklisted
    error AddressNotBlacklisted(address addr);

    /// @notice Thrown when address is 0x0
    error InvalidAddress();

    /// @notice Thrown when an address is blacklisted or quota exceeded
    error AddressBlacklistedOrQuotaExceeded(address addr, string message);

    /// @notice Thrown when a non-registered listener tries to perform an action
    error NotRegisteredListener(address listener);

    /// @notice Thrown when trying to register an already registered listener
    error AlreadyRegisteredListener(address listener);

    /// @notice Thrown when an invalid caller is provided
    error InvalidCaller();

    /// @notice Thrown when an invalid request ID is provided
    error InvalidRequestId();

    /// @notice Thrown when trying to fulfill an already fulfilled request
    error AlreadyFulfilled();

    // ========== FUNCTIONS ==========

    /// @notice Request execution of a task
    function requestExecution(
        string calldata methodSignature,
        bytes calldata input,
        bytes32 codeHash,
        DOTypes.ExecutionType executionType
    ) external returns (uint256);
}
