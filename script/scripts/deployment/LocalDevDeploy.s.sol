// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {MockToken} from "test/support/mocks/MockToken.sol";
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {DelphiFactory} from "src/factory/DelphiFactory.sol";
import {IDelphiFactory} from "src/factory/IDelphiFactory.sol";

/// @title LocalDevDeploy - Deploy the Delphi stack for local development
/// @notice Deploys the real Delphi contracts backed by a MockToken for easy token dispensing.
contract LocalDevDeploy is Script {
    uint256 constant TOKEN_MINT_AMOUNT = 100_000_000e6; // 100M tokens (6 decimals)

    function run() external {
        vm.startBroadcast();

        address gensynFoundation = vm.envAddress("GENSYN_FOUNDATION");

        // Get msg.sender
        (, address msgSender,) = vm.readCallers();

        // 1. Deploy MockToken (6 decimals, deployer as admin, no initial mint)
        MockToken mockToken =
            new MockToken({name: "MockToken", symbol: "MOCK", _decimals: 6, admin: msgSender, initialAmount: 0});
        console.log("MockToken:", address(mockToken));

        // 2. Deploy LmsrGateway
        LmsrGateway gateway = new LmsrGateway(mockToken, msgSender);
        address gatewayAddr = address(gateway);
        console.log("LmsrGateway:", gatewayAddr);

        // 3. Deploy LmsrMarket (implementation for cloning)
        LmsrMarket marketImpl = new LmsrMarket({
            tradingFeesRecipient: gensynFoundation,
            gateway: gatewayAddr,
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: 0,
            oracleFee: 0
        });
        console.log("LmsrMarket (impl):", address(marketImpl));

        // 4. Deploy DelphiFactory
        DelphiFactory factory = new DelphiFactory({
            implementation: address(marketImpl), marketCreationFee: 0, marketCreationFeeRecipient: msgSender
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
            console.log(
                string.concat(
                    "Funded ", vm.toString(fundedAccounts[i]), " with ", vm.toString(TOKEN_MINT_AMOUNT), " tokens"
                )
            );
        }

        vm.stopBroadcast();
    }
}
