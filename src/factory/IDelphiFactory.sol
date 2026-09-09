// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Interfaces
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {IDelphiFactoryErrors} from "./IDelphiFactoryErrors.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";

// Libraries
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title IDelphiFactory
/// @notice Interface for the factory that deploys and registers Delphi market proxies.
/// @dev The factory is the sole entrypoint for creating markets; the gateway only serves
///      market proxies that exist in the factory's registry.
interface IDelphiFactory is IDelphiFactoryErrors {
    // ========== EVENTS ==========

    /// @notice Emitted when a new market proxy is deployed and initialized.
    /// @param deployer The market creator (caller of deployNewMarketProxy).
    /// @param implementation The market implementation the proxy delegates to.
    /// @param newMarketProxy The address of the newly deployed market proxy.
    /// @param newMarketConfig The market configuration the proxy was initialized with.
    /// @param newMarketMetadata The verifiable URI for the market metadata.
    event NewMarketProxy(
        address indexed deployer,
        address indexed implementation,
        address newMarketProxy,
        ILmsrMarketTypes.MarketConfig newMarketConfig,
        IDelphiMarket.VerifiableUri newMarketMetadata
    );

    // ========== IMMUTABLES ==========

    /// @notice The market implementation cloned for every new market (EIP-1167 minimal proxy).
    function IMPLEMENTATION() external view returns (address);
    /// @notice The ERC-20 token used by all markets deployed by this factory.
    function TOKEN() external view returns (IERC20Metadata);
    /// @notice The fee charged on market creation, in token decimals.
    function MARKET_CREATION_FEE() external view returns (uint256);
    /// @notice The portion of the market creation fee (KEEPER_FEE + ORACLE_FEE) forwarded to the market proxy.
    function SETTLEMENT_FEES() external view returns (uint256);
    /// @notice The address that receives the market creation fee remainder (after settlement fees).
    function MARKET_CREATION_FEE_RECIPIENT() external view returns (address);

    // ========== FUNCTIONS ==========

    /// @notice Deploys, funds, and initializes a new market proxy. Permissionless.
    /// @dev Pulls `initialDeposit_` (and, if configured, MARKET_CREATION_FEE) from the caller,
    ///      who must have approved the factory beforehand.
    /// @param initialDeposit_ The initial market funding, in token decimals (must cover maxLoss = b·ln(outcomeCount)).
    /// @param newMarketConfig_ The market configuration.
    /// @param newMarketMetadata The verifiable URI for the market metadata.
    /// @return newMarketProxy The address of the newly deployed market proxy.
    function deployNewMarketProxy(
        uint256 initialDeposit_,
        ILmsrMarketTypes.MarketConfig calldata newMarketConfig_,
        IDelphiMarket.VerifiableUri calldata newMarketMetadata
    ) external returns (address newMarketProxy);

    // ========== VIEWS ==========

    // Market Proxies

    /// @return The total number of market proxies deployed by this factory.
    function getTotalMarketProxiesCount() external view returns (uint256);

    /// @notice Returns a page of deployed market proxies.
    /// @param firstIdx The first index to return (inclusive).
    /// @param lastIdx The last index to return (inclusive).
    /// @return The market proxy addresses in the requested range.
    function getMarketProxies(uint256 firstIdx, uint256 lastIdx) external view returns (address[] memory);

    /// @param marketProxy The address to check.
    /// @return True if the address is a market proxy deployed by this factory.
    function marketProxyExists(address marketProxy) external view returns (bool);

    /// @param marketProxies The addresses to check.
    /// @return Whether each address is a market proxy deployed by this factory.
    function marketProxiesExist(address[] calldata marketProxies) external view returns (bool[] memory);
}
