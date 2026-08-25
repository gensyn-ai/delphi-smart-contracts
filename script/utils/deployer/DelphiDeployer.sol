// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {DynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/DynamicParimutuelGateway.sol";
import {DynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/DynamicParimutuelMarket.sol";
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";

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
        DynamicParimutuelGateway dynamicParimutuelGateway;
        DynamicParimutuelMarket dynamicParimutuelImplementation;
        DelphiFactory delphiFactory;
    }

    // Libraries
    using stdJson for string;

    function _deployDelphi(DelphiConfig memory args) internal returns (DelphiAddresses memory) {
        _verifyDelphiArgs(args);

        // Deploy DynamicParimutuel Gateway
        DynamicParimutuelGateway dynamicParimutuelGateway = new DynamicParimutuelGateway(args.token, args.gatewayOwner);

        // Deploy DynamicParimutuel Implementation
        DynamicParimutuelMarket dynamicParimutuelImplementation = new DynamicParimutuelMarket({
            tradingFeesRecipient: args.tradingFeesRecipient,
            gateway: address(dynamicParimutuelGateway),
            tradingFeesRecipientPct: args.tradingFeesRecipientPct,
            keeperFee: args.keeperFee,
            oracleFee: args.oracleFee
        });

        // Deploy DelphiFactory implementation
        DelphiFactory delphiFactory = new DelphiFactory({
            implementation: address(dynamicParimutuelImplementation),
            marketCreationFee: args.marketCreationFee,
            marketCreationFeeRecipient: args.marketCreationFeeRecipient
        });

        // Initialize Gateway
        dynamicParimutuelGateway.initialize({delphiFactory_: delphiFactory});

        return DelphiAddresses({
            dynamicParimutuelGateway: dynamicParimutuelGateway,
            dynamicParimutuelImplementation: dynamicParimutuelImplementation,
            delphiFactory: delphiFactory
        });
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
            keeperFee: json.readUint(".factory.keeperFee"),
            oracleFee: json.readUint(".factory.oracleFee"),
            token: IERC20Metadata(json.readAddress(".token")),
            gatewayOwner: json.readAddress(".gateway.owner")
        });
    }
}
