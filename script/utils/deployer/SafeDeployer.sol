// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {GnosisSafeL2, GnosisSafe} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@safe-contracts/proxies/GnosisSafeProxyFactory.sol";

// Types
import {Addresses} from "../Addresses.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract SafeDeployer {
    // Types
    struct SafeProxyConfig {
        address[] owners;
        uint256 threshold;
    }

    // Libraries
    using stdJson for string;

    function _deployTokenTimelockSafeProxy(Addresses memory addresses, SafeProxyConfig memory config)
        internal
        returns (Addresses memory)
    {
        // Deploy proxy
        addresses.tokenTimelockSafeProxy = _deploySafeProxy(addresses, config);

        // Return addresses
        return addresses;
    }

    function _deployDelphiTimelockSafeProxy(Addresses memory addresses, SafeProxyConfig memory config)
        internal
        returns (Addresses memory)
    {
        // Deploy proxy
        addresses.delphiTimelockSafeProxy = _deploySafeProxy(addresses, config);

        // Return addresses
        return addresses;
    }

    function _deployDelphiSafeProxy(Addresses memory addresses, SafeProxyConfig memory config)
        internal
        returns (Addresses memory)
    {
        // Deploy proxy
        addresses.delphiSafeProxy = _deploySafeProxy(addresses, config);

        // Return addresses
        return addresses;
    }

    function _deploySafeProxy(Addresses memory addresses, SafeProxyConfig memory config)
        private
        returns (GnosisSafeL2)
    {
        // Validate args
        _validateSafeArgs(config);

        // If no singleton, deploy it
        if (address(addresses.safeSingleton) == address(0)) {
            addresses.safeSingleton = new GnosisSafeL2();
        }

        // If no proxy factory, deploy it
        if (address(addresses.safeProxyFactory) == address(0)) {
            addresses.safeProxyFactory = new GnosisSafeProxyFactory();
        }

        // Build setup calldata
        bytes memory setupCalldata = abi.encodeCall(
            GnosisSafe.setup,
            (
                config.owners,
                config.threshold,
                address(0), // to
                "", // data
                address(0), // fallbackHandler
                address(0), // paymentToken
                0, // payment
                payable(0) // paymentReceiver
            )
        );

        // Deploy proxy
        return
            GnosisSafeL2(
                payable(addresses.safeProxyFactory.createProxy(address(addresses.safeSingleton), setupCalldata))
            );
    }

    function _validateSafeArgs(SafeProxyConfig memory config) private pure {
        require(config.owners.length > 0, "SafeDeployer | owners cannot be empty");
        require(config.threshold > 0, "SafeDeployer | threshold cannot be zero");
        require(config.threshold <= config.owners.length, "SafeDeployer | threshold cannot exceed owner count");
    }

    function _getSafeProxyConfigFromJson(string memory json, string memory key)
        internal
        pure
        returns (SafeProxyConfig memory)
    {
        return SafeProxyConfig({
            owners: json.readAddressArray(string.concat(key, ".owners")),
            threshold: json.readUint(string.concat(key, ".threshold"))
        });
    }
}

