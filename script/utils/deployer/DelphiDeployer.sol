// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {DelphiFactory} from "src/factory/DelphiFactory.sol";

// Interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract DelphiDeployer {
    struct DelphiConfig {
        address tradingFeesRecipient;
        address marketCreationFeeRecipient;
        uint256 marketCreationFee;
        uint256 keeperFee;
        uint256 oracleFee;
        uint256 tradingFeesRecipientPct;
        IERC20Metadata token;
        address gatewayOwner;
    }

    struct DelphiAddresses {
        LmsrGateway gateway;
        LmsrMarket implementation;
        DelphiFactory factory;
    }

    // Libraries
    using stdJson for string;

    function _deployDelphi(DelphiConfig memory args) internal returns (DelphiAddresses memory) {
        _verifyDelphiArgs(args);

        // Deploy Lmsr Gateway
        LmsrGateway gateway = new LmsrGateway(args.token, args.gatewayOwner);

        // Deploy Lmsr Implementation
        LmsrMarket implementation = new LmsrMarket({
            tradingFeesRecipient: args.tradingFeesRecipient,
            gateway: address(gateway),
            tradingFeesRecipientPct: args.tradingFeesRecipientPct,
            keeperFee: args.keeperFee,
            oracleFee: args.oracleFee
        });

        // Deploy DelphiFactory implementation
        DelphiFactory delphiFactory = new DelphiFactory({
            implementation: address(implementation),
            marketCreationFee: args.marketCreationFee,
            marketCreationFeeRecipient: args.marketCreationFeeRecipient
        });

        // Initialize Gateway
        gateway.initialize({delphiFactory_: delphiFactory});

        // Return DelphiAddresses
        return DelphiAddresses({gateway: gateway, implementation: implementation, factory: delphiFactory});
    }

    function _verifyDelphiArgs(DelphiConfig memory args) internal pure {
        require(args.tradingFeesRecipient != address(0), "Delphi | tradingFeesRecipient cannot be address 0");
        require(
            args.marketCreationFeeRecipient != address(0), "Delphi | marketCreationFeeRecipient cannot be address 0"
        );
        require(address(args.token) != address(0), "Delphi | token cannot be address 0");
        require(args.gatewayOwner != address(0), "Delphi | gatewayOwner cannot be address 0");
    }

    function _getDelphiConfigFromJson(string memory json) internal pure returns (DelphiConfig memory) {
        return DelphiConfig({
            tradingFeesRecipient: json.readAddress(".implementation.tradingFeesRecipient"),
            tradingFeesRecipientPct: json.readUint(".implementation.tradingFeesRecipientPct"),
            marketCreationFeeRecipient: json.readAddress(".factory.marketCreationFeeRecipient"),
            marketCreationFee: json.readUint(".factory.marketCreationFee"),
            keeperFee: json.readUint(".implementation.keeperFee"),
            oracleFee: json.readUint(".implementation.oracleFee"),
            token: IERC20Metadata(json.readAddress(".token.address")),
            gatewayOwner: json.readAddress(".gateway.owner")
        });
    }
}
