// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Interfaces
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDelphiFactoryErrors} from "./IDelphiFactoryErrors.sol";

// Libraries
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IDelphiFactory is IDelphiFactoryErrors {
    // ========== TYPES ==========
    struct ImplementationInfo {
        string label;
        EnumerableSet.AddressSet marketProxies;
    }

    struct NamedImplementation {
        address implementation;
        string label;
    }

    // ========== EVENTS ==========
    event NewMarketProxy(
        address indexed deployer,
        address indexed implementation,
        address newMarketProxy,
        IDelphiMarket.VerifiableUri newMarketMetadata
    );

    // ========== IMMUTABLES ==========
    function IMPLEMENTATION() external view returns (address);
    function TOKEN() external view returns (IERC20Metadata);
    function MARKET_CREATION_FEE() external view returns (uint256);
    function MIN_MARKET_CREATION_FEE() external view returns (uint256);
    function MAX_MARKET_CREATION_FEE() external view returns (uint256);
    function MARKET_CREATION_FEE_RECIPIENT() external view returns (address);

    // ========== FUNCTIONS ==========

    function deployNewMarketProxy(
        uint256 initialLiquidity_,
        IDelphiMarket.VerifiableUri calldata newMarketMetadata,
        bytes calldata newMarketInitializationCalldata
    ) external returns (address newMarketProxy);

    // ========== VIEWS ==========

    // Market Proxies
    function getTotalMarketProxiesCount() external view returns (uint256);
    function getMarketProxies(uint256 firstIdx, uint256 lastIdx) external view returns (address[] memory);
    function marketProxyExists(address marketProxy) external view returns (bool);
    function marketProxiesExist(address[] calldata marketProxies) external view returns (bool[] memory);
}
