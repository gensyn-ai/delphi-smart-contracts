// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {TestToken} from "src/token/TestToken.sol";
import {GensynFaucetUpgradeable} from "src/token/GensynFaucetUpgradeable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GnosisSafeL2} from "@safe-contracts/GnosisSafeL2.sol";
import {GnosisSafeProxyFactory} from "@safe-contracts/proxies/GnosisSafeProxyFactory.sol";

// Types
import {Addresses} from "script/utils/Addresses.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

// Logging
import {console2} from "forge-std/console2.sol";

library SetupMarketCreationUtils {
    // Types
    struct TokenDistributionConfig {
        uint256 faucetInitialFunds;
        address[] receivers;
        uint256 tokensPerReceiver;
    }

    // Libraries
    using stdJson for string;

    // ===== INTERNAL =====

    function getAddressesFromJson(string memory json) internal pure returns (Addresses memory) {
        return Addresses({
            safeSingleton: GnosisSafeL2(payable(json.readAddress(".deployment.safeSingleton"))),
            safeProxyFactory: GnosisSafeProxyFactory(json.readAddress(".deployment.safeProxyFactory")),
            tokenTimelockSafeProxy: GnosisSafeL2(payable(json.readAddress(".deployment.tokenTimelockSafeProxy"))),
            delphiTimelockSafeProxy: GnosisSafeL2(payable(json.readAddress(".deployment.delphiTimelockSafeProxy"))),
            delphiSafeProxy: GnosisSafeL2(payable(json.readAddress(".deployment.delphiSafeProxy"))),
            tokenTimelock: TimelockController(payable(json.readAddress(".deployment.tokenTimelock"))),
            delphiTimelock: TimelockController(payable(json.readAddress(".deployment.delphiTimelock"))),
            gensynTokenImplementation: TestToken(json.readAddress(".deployment.gensynTokenImplementation")),
            gensynTokenProxy: TestToken(json.readAddress(".deployment.gensynTokenProxy")),
            gensynFaucetImplementation: GensynFaucetUpgradeable(
                json.readAddress(".deployment.gensynFaucetImplementation")
            ),
            gensynFaucetProxy: GensynFaucetUpgradeable(json.readAddress(".deployment.gensynFaucetProxy"))
        });
    }

    function getTokenDistributionConfigFromJson(string memory json)
        internal
        pure
        returns (TokenDistributionConfig memory)
    {
        return TokenDistributionConfig({
            faucetInitialFunds: json.readUint(".tokenDistributionConfig.faucetInitialFunds"),
            tokensPerReceiver: json.readUint(".tokenDistributionConfig.tokensPerReceiver"),
            receivers: json.readAddressArray(".tokenDistributionConfig.receivers")
        });
    }

    function distributeTokens(
        Addresses memory deployment,
        TokenDistributionConfig memory tokenDistributionConfig,
        address leftoverRecipient,
        address deployer
    ) internal {
        // Fund faucet
        if (tokenDistributionConfig.faucetInitialFunds > 0) {
            deployment.gensynTokenProxy
                .transfer(address(deployment.gensynFaucetProxy), tokenDistributionConfig.faucetInitialFunds);
        }

        // Fund receivers
        for (uint256 i = 0; i < tokenDistributionConfig.receivers.length; i++) {
            deployment.gensynTokenProxy
                .transfer(tokenDistributionConfig.receivers[i], tokenDistributionConfig.tokensPerReceiver);
        }

        // Send leftover tokens to leftoverRecipient
        uint256 leftoverBalance = deployment.gensynTokenProxy.balanceOf(deployer);
        deployment.gensynTokenProxy.transfer(leftoverRecipient, leftoverBalance);
    }

    function logAddresses(Addresses memory deployment) internal pure {
        // Log
        console2.log("Safe Singleton:", address(deployment.safeSingleton));
        console2.log("Safe Proxy Factory:", address(deployment.safeProxyFactory));
        console2.log("Token Timelock Safe Proxy:", address(deployment.tokenTimelockSafeProxy));
        console2.log("Delphi Timelock Safe Proxy:", address(deployment.delphiTimelockSafeProxy));
        console2.log("Delphi Safe Proxy:", address(deployment.delphiSafeProxy));
        console2.log("Token Timelock:", address(deployment.tokenTimelock));
        console2.log("Delphi Timelock:", address(deployment.delphiTimelock));
        console2.log("Gensyn Token Implementation:", address(deployment.gensynTokenImplementation));
        console2.log("Gensyn Token Proxy:", address(deployment.gensynTokenProxy));
        console2.log("Gensyn Faucet Implementation:", address(deployment.gensynFaucetImplementation));
        console2.log("Gensyn Faucet Proxy:", address(deployment.gensynFaucetProxy));
    }
}
