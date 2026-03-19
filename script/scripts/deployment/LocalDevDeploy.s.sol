// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockToken} from "src/mock/MockToken.sol";
import {DynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/DynamicParimutuelGateway.sol";
import {DynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/DynamicParimutuelMarket.sol";
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";
import {IDelphiFactory} from "src/delphi/factory/IDelphiFactory.sol";

/// @title LocalDevDeploy - Deploy the Delphi stack for local development
/// @notice Deploys the real Delphi contracts backed by a MockToken for easy token dispensing.
contract LocalDevDeploy is Script {
    uint256 constant TOKEN_MINT_AMOUNT = 100_000_000e6; // 100M tokens (6 decimals)

    function run() external {
        vm.startBroadcast();

        address gensynFoundation = vm.envAddress("GENSYN_FOUNDATION");

        // 1. Deploy MockToken (6 decimals, deployer as admin, no initial mint)
        MockToken mockToken = new MockToken({_decimals: 6, admin: msg.sender, initialAmount: 0});
        console.log("MockToken:", address(mockToken));

        // 2. Deploy DynamicParimutuelGateway
        DynamicParimutuelGateway gateway = new DynamicParimutuelGateway(mockToken);
        address gatewayAddr = address(gateway);
        console.log("DynamicParimutuelGateway:", gatewayAddr);

        // 3. Deploy DynamicParimutuelMarket (implementation for cloning)
        DynamicParimutuelMarket marketImpl = new DynamicParimutuelMarket({
            tradingFeesRecipient: gensynFoundation, gateway: gatewayAddr, tradingFeesRecipientPct: 0.1e18
        });
        console.log("DynamicParimutuelMarket (impl):", address(marketImpl));

        // 4. Deploy DelphiFactory
        DelphiFactory factory = new DelphiFactory({
            implementation: address(marketImpl), marketCreationFee: 0, marketCreationFeeRecipient: msg.sender
        });
        address factoryAddr = address(factory);
        console.log("DelphiFactory:", factoryAddr);

        // 5. Initialize gateway with factory reference
        gateway.initialize(IDelphiFactory(factoryAddr));
        console.log("Gateway initialized with factory");

        console.log("Gensyn Foundation Address:", gensynFoundation);

        // 6. Fund accounts with mock tokens
        address[] memory fundedAccounts = vm.envAddress("TOKEN_FUNDED_ACCOUNTS", ",");
        for (uint256 i = 0; i < fundedAccounts.length; i++) {
            mockToken.mint(fundedAccounts[i], TOKEN_MINT_AMOUNT);
            console.log("Funded %s with 1M tokens", fundedAccounts[i]);
        }

        vm.stopBroadcast();
    }
}
