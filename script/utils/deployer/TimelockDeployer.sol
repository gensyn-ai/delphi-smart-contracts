// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

// Types
import {Addresses} from "script/utils/Addresses.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract TimelockDeployer {
    // Types
    struct TimelockConfig {
        uint256 minDelay;
    }

    // Libraries
    using stdJson for string;

    function _deployTokenTimelock(Addresses memory addresses, address proposer, TimelockConfig memory config)
        internal
        returns (Addresses memory)
    {
        addresses.tokenTimelock = _deployTimelock(proposer, config);
        return addresses;
    }

    function _deployDelphiTimelock(Addresses memory addresses, address proposer, TimelockConfig memory config)
        internal
        returns (Addresses memory)
    {
        addresses.delphiTimelock = _deployTimelock(proposer, config);
        return addresses;
    }

    function _deployTimelock(address proposer, TimelockConfig memory config) private returns (TimelockController) {
        // Validate args
        _validateTimelockArgs(proposer, config);

        // Build proposers
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        // Build executors
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Note: Let anyone execute

        // Deploy timelock
        return new TimelockController({
            minDelay: config.minDelay,
            proposers: proposers,
            executors: executors,
            admin: address(0) // Note: No admin
        });
    }

    function _validateTimelockArgs(address proposer, TimelockConfig memory config) private pure {
        require(proposer != address(0), "TimelockDeployer | proposer cannot be address(0)");
        require(config.minDelay > 0, "TimelockDeployer | minDelay must be > 0");
    }

    // Todo: fix
    function _getTimelockConfigFromJson(string memory json, string memory path)
        internal
        pure
        returns (TimelockConfig memory)
    {
        return TimelockConfig({minDelay: uint256(json.readUint(string.concat(path, ".minDelay")))});
    }
}
