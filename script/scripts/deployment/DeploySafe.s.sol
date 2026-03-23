// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";

// Contracts
import {GnosisSafeL2, GnosisSafe} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@safe-contracts/proxies/GnosisSafeProxyFactory.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract DeploySafe_Script is BaseScript {
    struct DeploySafeArgs {
        GnosisSafeL2 singleton;
        GnosisSafeProxyFactory proxyFactory;
        address[] owners;
        uint256 threshold;
    }

    using stdJson for string;

    function run()
        external
        broadcast
        returns (GnosisSafeL2 singleton, GnosisSafeProxyFactory proxyFactory, GnosisSafeL2 safeProxy)
    {
        // Get deploy safe args from JSON
        DeploySafeArgs memory args =
            _getDeploySafeArgsFromJson({json: _getJson({path_: "/script/input/deployment/DeploySafe.json"})});

        // Validate args
        _validateArgs(args);

        // If no singleton, deploy it
        singleton = address(args.singleton) == address(0) ? new GnosisSafeL2() : args.singleton;

        // If no proxy factory, deploy it
        proxyFactory = address(args.proxyFactory) == address(0) ? new GnosisSafeProxyFactory() : args.proxyFactory;

        // Deploy proxy
        safeProxy = GnosisSafeL2(
            payable(proxyFactory.createProxy({
                    singleton: address(singleton),
                    data: abi.encodeCall(
                        GnosisSafe.setup,
                        (
                            args.owners,
                            args.threshold,
                            address(0), // to
                            "", // data
                            address(0), // fallbackHandler
                            address(0), // paymentToken
                            0, // payment
                            payable(0) // paymentReceiver
                        )
                    )
                }))
        );
    }

    function _getDeploySafeArgsFromJson(string memory json) private pure returns (DeploySafeArgs memory) {
        return DeploySafeArgs({
            singleton: GnosisSafeL2(payable(json.readAddress(".addresses.singleton"))),
            proxyFactory: GnosisSafeProxyFactory(json.readAddress(".addresses.proxyFactory")),
            owners: json.readAddressArray(".config.owners"),
            threshold: json.readUint(".config.threshold")
        });
    }

    function _validateArgs(DeploySafeArgs memory args) private pure {
        require(args.owners.length >= 3, "DeploySafe: owner count must be at least 3");
        require(args.threshold >= 2, "DeploySafe: threshold must be at least 2");
        require(args.threshold < args.owners.length, "DeploySafe: threshold must be below owner count");
    }
}
