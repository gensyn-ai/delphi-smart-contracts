// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    ERC20BurnableUpgradeable,
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {
    ERC20PermitUpgradeable,
    NoncesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TestToken
 * @notice Upgradeable ERC20 token (with burnability, voting checkpoints and EIP-2612 gasless approvals)
 */
contract TestToken is
    ERC20BurnableUpgradeable,
    ERC20VotesUpgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    uint8 private _decimals;

    /**
     * @notice Implementation constructor.
     * @dev Disables all initializers on this implementation contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Implementation initializer.
     * @dev Initializes all required parent state.
     */
    function initialize(
        string calldata name_,
        string calldata symbol_,
        uint256 initialSupply_,
        uint8 decimals_,
        address admin_,
        address recipient_
    ) external initializer {
        // Initialize base
        __ERC20_init(name_, symbol_);

        // Initialize all direct parents
        // __ERC20Burnable_init(); // Note: does nothing
        // __ERC20Votes_init(); // Note: does nothing
        __ERC20Permit_init(name_);
        // __AccessControl_init(); // Note: does nothing
        // __UUPSUpgradeable_init(); // Note: does nothing

        // Initialize self
        __TestToken_init(admin_, recipient_, initialSupply_);

        // Set decimals
        _decimals = decimals_;
    }

    /**
     * @notice Internal initializer for TestToken-specific state.
     * @dev Restricted to initializer context by "onlyInitializing" modifier.
     * @param admin_ Address to receive the DEFAULT_ADMIN_ROLE.
     * @param recipient_ Address to receive the intitialSupply.
     * @param initialSupply The initial supply to mint to the recipient.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __TestToken_init(address admin_, address recipient_, uint256 initialSupply) internal onlyInitializing {
        require(admin_ != address(0), "admin should not be address(0)");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _mint(recipient_, initialSupply);
    }

    // ===== REQUIRED OVERRIDES =====

    /**
     * @notice ERC20 functionality for managing balance updates.
     * @dev Required override.
     * @param from The address tokens are moved from.
     * @param to The address tokens are moved to.
     * @param value The amount of tokens moved.
     */
    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        ERC20VotesUpgradeable._update(from, to, value);
    }

    /**
     * @notice ERC20Permit functionality for nonce tracking.
     * @dev Required override.
     * @param owner The address whose nonce is being queried.
     * @return The current nonce used for the owner's EIP-2612 signatures.
     */
    function nonces(address owner)
        public
        view
        virtual
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return ERC20PermitUpgradeable.nonces(owner);
    }

    /**
     * @notice UUPS upgrade authorization hook.
     * @dev Required override.
     * @dev Restricts upgrades to accounts with {DEFAULT_ADMIN_ROLE}.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
