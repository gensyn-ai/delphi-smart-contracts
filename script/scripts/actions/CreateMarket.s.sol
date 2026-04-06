// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";

// Contracts
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";

// Interfaces
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract CreateMarket_Script is BaseScript {
    // Libraries
    using stdJson for string;

    struct CreateMarketConfig {
        DelphiFactory delphiFactory;
        uint256 initialLiquidity;
        IDelphiMarket.VerifiableUri newMarketMetadata;
        IDynamicParimutuelMarket.MarketConfig newMarketConfig;
    }

    function run() external broadcast returns (address) {
        string memory json = _getJson("/script/input/actions/CreateMarket.json");

        CreateMarketConfig memory config = _getCreateMarketConfigFromJson(json);
        return config.delphiFactory
            .deployNewMarketProxy({
                initialLiquidity_: config.initialLiquidity,
                newMarketMetadata_: config.newMarketMetadata,
                newMarketInitializationCalldata_: abi.encode(config.newMarketConfig)
            });
    }

    // ========== HELPERS ==========

    function _getCreateMarketConfigFromJson(string memory json) internal pure returns (CreateMarketConfig memory) {
        return CreateMarketConfig({
            delphiFactory: DelphiFactory(json.readAddress(".delphiFactory")),
            initialLiquidity: json.readUint(".initialLiquidity"),
            newMarketMetadata: _getVerifiableUriFromJson(json, ".newMarketMetadata"),
            newMarketConfig: IDynamicParimutuelMarketTypes.MarketConfig({
                outcomeCount: json.readUint(".newMarketConfig.outcomeCount"),
                b: json.readUint(".newMarketConfig.b"),
                tradingFee: json.readUint(".newMarketConfig.tradingFee"),
                tradingDeadline: json.readUint(".newMarketConfig.tradingDeadline"),
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
