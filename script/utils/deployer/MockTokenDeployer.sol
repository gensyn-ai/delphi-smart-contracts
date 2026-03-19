// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {MockToken} from "src/mock/MockToken.sol";

// Interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockTokenDeployer {
    // Types
    struct MockTokenConfig {
        uint8 decimals;
        address admin;
        uint256 initialSupply;
    }

    function _deployMockToken(MockTokenConfig memory config) internal returns (IERC20Metadata) {
        // Validate args
        _validateMockTokenArgs(config);

        return new MockToken(config.decimals, config.admin, config.initialSupply);
    }

    function _validateMockTokenArgs(MockTokenConfig memory config) private pure {
        require(config.decimals <= 18, "MockToken | decimals must be <= 18");
        require(config.decimals >= 6, "MockToken | decimals must be >= 6");
        require(config.admin != address(0), "MockToken | admin cannot be the zero address");
    }
}
