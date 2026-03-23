// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {TestToken} from "src/token/TestToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Types
import {Addresses} from "../Addresses.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract GensynTokenDeployer {
    // Types
    struct GensynTokenConfig {
        string name;
        string symbol;
        uint256 initialSupply;
        uint8 decimals;
    }

    // Libraries
    using stdJson for string;

    function _deployGensynTokenProxy(address deployer, Addresses memory addresses, GensynTokenConfig memory config)
        internal
        returns (Addresses memory)
    {
        // Validate args
        _validateGensynTokenArgs(deployer, addresses, config);

        // If no implementation, deploy it
        if (address(addresses.gensynTokenImplementation) == address(0)) {
            addresses.gensynTokenImplementation = new TestToken();
        }

        // Deploy Proxy
        addresses.gensynTokenProxy = TestToken(
            address(
                new ERC1967Proxy({
                    implementation: address(addresses.gensynTokenImplementation),
                    _data: abi.encodeCall(
                        TestToken.initialize,
                        (
                            config.name, // name
                            config.symbol, // symbol
                            config.initialSupply, // initialSupply
                            config.decimals, // decimals
                            address(addresses.tokenTimelock), // admin
                            deployer // recipient (now deployer, later to be transferred)
                        )
                    )
                })
            )
        );

        // Return addresses
        return addresses;
    }

    function _validateGensynTokenArgs(address deployer, Addresses memory addresses, GensynTokenConfig memory config)
        private
        pure
    {
        require(bytes(config.name).length > 0, "GensynTokenDeployer | name cannot be empty");
        require(bytes(config.symbol).length > 0, "GensynTokenDeployer | symbol cannot be empty");
        require(config.initialSupply > 0, "GensynTokenDeployer | initialSupply cannot be 0");
        require(config.decimals >= 6, "GensynTokenDeployer | decimals cannot be < 6");
        require(config.decimals <= 18, "GensynTokenDeployer | decimals cannot be > 18");
        require(
            address(addresses.tokenTimelock) != address(0), "GensynTokenDeployer | tokenTimelock cannot be address(0)"
        );
        require(deployer != address(0), "GensynTokenDeployer | deployer cannot be address(0)");
    }

    function _getGensynTokenConfigFromJson(string memory json) internal pure returns (GensynTokenConfig memory) {
        return GensynTokenConfig({
            name: json.readString(".deployAllConfig.gensynToken.name"),
            symbol: json.readString(".deployAllConfig.gensynToken.symbol"),
            initialSupply: uint256(json.readUint(".deployAllConfig.gensynToken.initialSupply")),
            decimals: uint8(json.readUint(".deployAllConfig.gensynToken.decimals"))
        });
    }
}
