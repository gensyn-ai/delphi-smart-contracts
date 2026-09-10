// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockToken is ERC20Permit {
    // Errors
    error BlacklistedSender(address sender);
    error BlacklistedReceiver(address receiver);

    // Immutables
    uint8 internal immutable _DECIMALS;
    address public immutable ADMIN;

    // State variables
    mapping(address => bool) public blacklisted;

    // Constructor
    constructor(string memory name, string memory symbol, uint8 _decimals, address admin, uint256 initialAmount)
        ERC20Permit(name)
        ERC20(name, symbol)
    {
        // Set immutables
        _DECIMALS = _decimals;
        ADMIN = admin;

        // Mint initial amount to admin
        _mint(admin, initialAmount);
    }

    // External functions
    function mint(address recipient, uint256 amount) external {
        require(msg.sender == ADMIN);
        _mint(recipient, amount);
    }

    function blacklist(address account) external {
        require(msg.sender == ADMIN);
        require(!blacklisted[account], "Account already blacklisted");
        blacklisted[account] = true;
    }

    function unblacklist(address account) external {
        require(msg.sender == ADMIN);
        require(blacklisted[account], "Account not blacklisted");
        blacklisted[account] = false;
    }

    // External views
    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    function isBlacklisted(address account) external view returns (bool) {
        return blacklisted[account];
    }

    // Internal functions
    function _update(address from, address to, uint256 value) internal override {
        if (blacklisted[from]) {
            revert BlacklistedSender(from);
        } else if (blacklisted[to]) {
            revert BlacklistedReceiver(to);
        } else {
            super._update(from, to, value);
        }
    }
}
