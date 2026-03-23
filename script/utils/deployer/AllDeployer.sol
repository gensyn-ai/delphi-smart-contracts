// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeDeployer} from "./SafeDeployer.sol";
import {TimelockDeployer} from "./TimelockDeployer.sol";
import {GensynTokenDeployer} from "./GensynTokenDeployer.sol";
import {GensynFaucetDeployer} from "./GensynFaucetDeployer.sol";
import {Addresses} from "script/utils/Addresses.sol";

contract AllDeployer is SafeDeployer, TimelockDeployer, GensynTokenDeployer, GensynFaucetDeployer {
    struct DeployAllConfig {
        SafeProxyConfig tokenTimelockSafeProxy;
        SafeProxyConfig delphiTimelockSafeProxy;
        SafeProxyConfig delphiSafeProxy;
        TimelockConfig tokenTimelock;
        TimelockConfig delphiTimelock;
        GensynTokenConfig gensynToken;
        GensynFaucetConfig gensynFaucet;
    }

    // Todo: make the ownership transfers part of this function
    function _deployAll(address deployer, Addresses memory addresses, DeployAllConfig memory config)
        internal
        returns (Addresses memory)
    {
        if (address(addresses.tokenTimelockSafeProxy) == address(0)) {
            addresses = _deployTokenTimelockSafeProxy(addresses, config.tokenTimelockSafeProxy);
        }

        if (address(addresses.delphiTimelockSafeProxy) == address(0)) {
            addresses = _deployDelphiTimelockSafeProxy(addresses, config.delphiTimelockSafeProxy);
        }

        if (address(addresses.delphiSafeProxy) == address(0)) {
            addresses = _deployDelphiSafeProxy(addresses, config.delphiSafeProxy);
        }

        if (address(addresses.tokenTimelock) == address(0)) {
            addresses = _deployTokenTimelock({
                addresses: addresses, proposer: address(addresses.tokenTimelockSafeProxy), config: config.tokenTimelock
            });
        }

        if (address(addresses.delphiTimelock) == address(0)) {
            addresses = _deployDelphiTimelock({
                addresses: addresses,
                proposer: address(addresses.delphiTimelockSafeProxy),
                config: config.delphiTimelock
            });
        }

        if (address(addresses.gensynTokenProxy) == address(0)) {
            addresses = _deployGensynTokenProxy(deployer, addresses, config.gensynToken);
        }

        if (address(addresses.gensynFaucetProxy) == address(0)) {
            (addresses.gensynFaucetProxy, addresses.gensynFaucetImplementation) = _deployGensynFaucetProxy(
                address(addresses.gensynTokenProxy),
                address(addresses.delphiTimelock),
                address(addresses.delphiSafeProxy),
                address(addresses.gensynFaucetImplementation),
                config.gensynFaucet
            );
        }

        // Return addresses
        return addresses;
    }

    function _getDeployAllConfigFromJson(string memory json)
        internal
        pure
        returns (DeployAllConfig memory deployAllConfig)
    {
        deployAllConfig = DeployAllConfig({
            tokenTimelockSafeProxy: _getSafeProxyConfigFromJson(json, ".deployAllConfig.tokenTimelockSafeProxy"),
            delphiTimelockSafeProxy: _getSafeProxyConfigFromJson(json, ".deployAllConfig.delphiTimelockSafeProxy"),
            delphiSafeProxy: _getSafeProxyConfigFromJson(json, ".deployAllConfig.delphiSafeProxy"),
            tokenTimelock: _getTimelockConfigFromJson(json, ".deployAllConfig.tokenTimelock"),
            delphiTimelock: _getTimelockConfigFromJson(json, ".deployAllConfig.delphiTimelock"),
            gensynToken: _getGensynTokenConfigFromJson(json),
            gensynFaucet: _getGensynFaucetConfigFromJson(json)
        });
    }
}

