// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {TruebitOracleRelayer} from "src/oracle/TruebitOracleRelayer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";

contract TruebitOracleRelayerDeployer {
    // Errors
    error OwnerIsZeroAddress();
    error GatewayIsZeroAddress();
    error OracleFeeRecipientIsZeroAddress();
    error WatchTowerIsZeroAddress();
    error ExecutionTimeoutIsZero();
    error ImplementationHasNoCode(address implementation);
    error ImplementationWatchTowerMismatch(address expected, address actual);
    error ImplementationGatewayMismatch(address expected, address actual);
    error ImplementationExecutionTimeoutMismatch(uint256 expected, uint256 actual);
    error ImplementationAsyncMismatch(bool expected, bool actual);

    function _deployTruebitOracleRelayerProxy(
        address watchTower,
        ILmsrGateway gateway,
        uint256 executionTimeout,
        bool async_,
        address implementation,
        TruebitOracleRelayer.InitParams memory params
    ) internal returns (TruebitOracleRelayer proxy, TruebitOracleRelayer impl) {
        _validateArgs(watchTower, gateway, executionTimeout, params);

        // If no implementation provided, deploy one
        if (implementation == address(0)) {
            impl = new TruebitOracleRelayer(watchTower, gateway, executionTimeout, async_);
        } else {
            // Reusing an existing implementation: ensure it is a contract whose constructor-set immutables
            // match the requested configuration, so we never deploy a proxy against stale/misconfigured
            // bytecode.
            _validateReusedImplementation(implementation, watchTower, gateway, executionTimeout, async_);
            impl = TruebitOracleRelayer(implementation);
        }

        // Deploy proxy
        proxy = TruebitOracleRelayer(
            address(new ERC1967Proxy(address(impl), abi.encodeCall(TruebitOracleRelayer.initialize, (params))))
        );
    }

    function _validateArgs(
        address watchTower,
        ILmsrGateway gateway,
        uint256 executionTimeout,
        TruebitOracleRelayer.InitParams memory params
    ) private pure {
        if (watchTower == address(0)) revert WatchTowerIsZeroAddress();
        if (address(gateway) == address(0)) revert GatewayIsZeroAddress();
        if (executionTimeout == 0) revert ExecutionTimeoutIsZero();
        if (params.owner == address(0)) revert OwnerIsZeroAddress();
        if (params.oracleFeeRecipient == address(0)) revert OracleFeeRecipientIsZeroAddress();
    }

    /// @dev Validates that a supplied (pre-existing) implementation address is a contract whose
    ///      constructor-set immutables match the requested deployment configuration.
    function _validateReusedImplementation(
        address implementation,
        address watchTower,
        ILmsrGateway gateway,
        uint256 executionTimeout,
        bool async_
    ) private view {
        if (implementation.code.length == 0) revert ImplementationHasNoCode(implementation);

        TruebitOracleRelayer impl = TruebitOracleRelayer(implementation);

        if (address(impl.WATCHTOWER()) != watchTower) {
            revert ImplementationWatchTowerMismatch(watchTower, address(impl.WATCHTOWER()));
        }
        if (address(impl.GATEWAY()) != address(gateway)) {
            revert ImplementationGatewayMismatch(address(gateway), address(impl.GATEWAY()));
        }
        if (impl.EXECUTION_TIMEOUT() != executionTimeout) {
            revert ImplementationExecutionTimeoutMismatch(executionTimeout, impl.EXECUTION_TIMEOUT());
        }
        if (impl.ASYNC() != async_) {
            revert ImplementationAsyncMismatch(async_, impl.ASYNC());
        }
    }
}
