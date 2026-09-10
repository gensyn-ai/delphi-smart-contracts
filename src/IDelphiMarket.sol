// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";

/// @title IDelphiMarket
/// @notice Minimal market interface the factory relies on to deploy and initialize market proxies.
interface IDelphiMarket {
    /// @notice A URI whose content can be verified against an on-chain hash.
    struct VerifiableUri {
        /// @dev Location of the market metadata (e.g. an object-storage or IPFS URI).
        string uri;
        /// @dev Hash of the content behind `uri`, so off-chain consumers can verify integrity.
        bytes32 uriContentHash;
    }

    /// @notice The ERC-20 token the market trades in.
    function TOKEN() external view returns (IERC20Metadata);

    /// @notice Initializes a new market proxy. Called once by the factory right after cloning.
    /// @param marketCreator_ The address that created (and funded) the market.
    /// @param newMarketConfig_ The market configuration.
    /// @param newMarketMetadata_ The verifiable URI for the market metadata.
    function initialize(
        address marketCreator_,
        ILmsrMarketTypes.MarketConfig calldata newMarketConfig_,
        VerifiableUri calldata newMarketMetadata_
    ) external;

    /// @return The market's metadata as a verifiable URI.
    function getMarketMetadata() external view returns (VerifiableUri memory);
}
