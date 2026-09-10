// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";

// Contracts
import {DelphiFactory} from "src/factory/DelphiFactory.sol";

// Interfaces
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract CreateMarket_Script is BaseScript {
    // Libraries
    using stdJson for string;

    struct CreateMarketConfig {
        DelphiFactory delphiFactory;
        uint256 initialDeposit;
        IDelphiMarket.VerifiableUri newMarketMetadata;
        ILmsrMarket.MarketConfig newMarketConfig;
    }

    function run() external broadcast returns (address newMarketProxy) {
        // Get json
        string memory json = _getJson("/script/input/actions/CreateMarket.json");

        // Get config
        CreateMarketConfig memory config = _getCreateMarketConfigFromJson(json);

        // Get token
        IERC20 token = config.delphiFactory.TOKEN();

        // Get market creator
        (, address marketCreator,) = vm.readCallers();

        // Calculate required allowance
        uint256 requiredAllowance = config.initialDeposit + config.delphiFactory.MARKET_CREATION_FEE();

        // If market creator hasn't approved the delphi factory to spend the required allowance
        if (token.allowance(marketCreator, address(config.delphiFactory)) < requiredAllowance) {
            // Approve the delphi factory to spend the required allowance
            token.approve(address(config.delphiFactory), requiredAllowance);
        }

        // Interactions: Deploy new market proxy
        newMarketProxy = config.delphiFactory
            .deployNewMarketProxy({
                initialDeposit_: config.initialDeposit,
                newMarketConfig_: config.newMarketConfig,
                newMarketMetadata_: config.newMarketMetadata
            });
    }

    // ========== HELPERS ==========

    function _getCreateMarketConfigFromJson(string memory json) internal pure returns (CreateMarketConfig memory) {
        return CreateMarketConfig({
            delphiFactory: DelphiFactory(json.readAddress(".delphiFactory")),
            initialDeposit: json.readUint(".initialDeposit"),
            newMarketMetadata: _getVerifiableUriFromJson(json, ".newMarketMetadata"),
            newMarketConfig: ILmsrMarketTypes.MarketConfig({
                outcomeCount: json.readUint(".newMarketConfig.outcomeCount"),
                b: json.readUint(".newMarketConfig.b"),
                tradingFee: json.readUint(".newMarketConfig.tradingFee"),
                tradingDeadline: json.readUint(".newMarketConfig.tradingDeadline"),
                earliestResolveTime: json.readUint(".newMarketConfig.earliestResolveTime"),
                settlementDeadline: json.readUint(".newMarketConfig.settlementDeadline")
            })
        });
    }

    function _getVerifiableUriFromJson(string memory json, string memory path)
        internal
        pure
        returns (IDelphiMarket.VerifiableUri memory)
    {
        return IDelphiMarket.VerifiableUri({
            uri: json.readString(string.concat(path, ".uri")),
            uriContentHash: json.readBytes32(string.concat(path, ".uriContentHash"))
        });
    }
}
