// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {GensynFaucetUpgradeable} from "src/token/GensynFaucetUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Libraries
import {stdJson} from "forge-std/StdJson.sol";

contract GensynFaucetDeployer {
    // Errors
    error TokenMismatch(address expected, address actual);
    error TokenIsZeroAddress();
    error AdminIsZeroAddress();
    error DripManagerIsZeroAddress();
    error DripTimeIsZero();
    error DripAmountIsZero();

    // Types
    struct GensynFaucetConfig {
        uint256 dripTime;
        uint256 dripAmount;
    }

    // Libraries
    using stdJson for string;

    function _deployGensynFaucetProxy(
        address token,
        address admin,
        address dripManager,
        address implementation,
        GensynFaucetConfig memory config
    ) internal returns (GensynFaucetUpgradeable proxy, GensynFaucetUpgradeable impl) {
        _validateGensynFaucetArgs(token, admin, dripManager, config);

        // If there is no implementation, deploy it
        if (implementation == address(0)) {
            impl = new GensynFaucetUpgradeable({gensynTokenProxy: token});
        } else {
            impl = GensynFaucetUpgradeable(implementation);
            if (address(impl.GENSYN_TOKEN()) != token) revert TokenMismatch(token, address(impl.GENSYN_TOKEN()));
        }

        // Deploy proxy
        proxy = GensynFaucetUpgradeable(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        GensynFaucetUpgradeable.initialize, (admin, dripManager, config.dripTime, config.dripAmount)
                    )
                )
            )
        );
    }

    function _validateGensynFaucetArgs(
        address token,
        address admin,
        address dripManager,
        GensynFaucetConfig memory config
    ) private pure {
        if (token == address(0)) revert TokenIsZeroAddress();
        if (admin == address(0)) revert AdminIsZeroAddress();
        if (dripManager == address(0)) revert DripManagerIsZeroAddress();
        if (config.dripTime == 0) revert DripTimeIsZero();
        if (config.dripAmount == 0) revert DripAmountIsZero();
    }

    function _getGensynFaucetConfigFromJson(string memory json) internal pure returns (GensynFaucetConfig memory) {
        return GensynFaucetConfig({
            dripTime: uint256(json.readUint(".deployAllConfig.gensynFaucet.dripTime")),
            dripAmount: uint256(json.readUint(".deployAllConfig.gensynFaucet.dripAmount"))
        });
    }
}
