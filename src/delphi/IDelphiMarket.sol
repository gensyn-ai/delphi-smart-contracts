// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IDelphiMarket {
    struct VerifiableUri {
        string uri;
        bytes32 uriContentHash;
    }

    function TOKEN() external view returns (IERC20Metadata);

    function initialize(
        address marketCreator_,
        uint256 initialDeposit_,
        VerifiableUri calldata newMarketMetadata_,
        bytes calldata initializationCalldata_
    ) external;

    function getMarketMetadata() external view returns (VerifiableUri memory);
}
