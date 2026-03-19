// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseScript} from "script/utils/BaseScript.sol";
import {DelphiDeployer} from "script/utils/deployer/DelphiDeployer.sol";
import {MockTokenDeployer} from "script/utils/deployer/MockTokenDeployer.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";
import {SetupMarketCreationUtils} from "script/utils/SetupMarketCreationUtils.sol";

// Interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DeployDelphi_Script is DelphiDeployer, MockTokenDeployer, BaseScript {
    // Libraries
    using SetupMarketCreationUtils for string;
    using stdJson for string;

    function run() external broadcast returns (IERC20Metadata token, DelphiAddresses memory delphi) {
        // Get json
        string memory json = _getJson("/script/input/deployment/DeployDelphi.json");

        token = _getOrDeployToken(json);

        address tradingFeesRecipient = json.readAddress(".implementation.tradingFeesRecipient");
        uint256 tradingFeesRecipientPct = json.readUint(".implementation.tradingFeesRecipientPct");
        address marketCreationFeeRecipient = json.readAddress(".factory.marketCreationFeeRecipient");
        uint256 marketCreationFee = json.readUint(".factory.marketCreationFee");

        delphi = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: tradingFeesRecipient,
                marketCreationFeeRecipient: marketCreationFeeRecipient,
                marketCreationFee: marketCreationFee,
                tradingFeesRecipientPct: tradingFeesRecipientPct,
                token: token
            })
        );
    }

    function _getOrDeployToken(string memory json) internal returns (IERC20Metadata) {
        address tokenFromConfig = json.readAddress(".token.address");
        if (tokenFromConfig != address(0)) {
            return IERC20Metadata(tokenFromConfig);
        }

        address tokenAdmin = json.readAddress(".token.config.admin");
        uint256 tokenInitialAmount = json.readUint(".token.config.initialAmount");

        // Deploy Mock Token
        return _deployMockToken(MockTokenConfig({admin: tokenAdmin, decimals: 6, initialSupply: tokenInitialAmount}));
    }
}
