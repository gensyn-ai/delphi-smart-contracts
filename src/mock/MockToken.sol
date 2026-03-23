// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20("MockToken", "MT") {
    uint8 internal immutable _DECIMALS;

    address public immutable ADMIN;

    constructor(uint8 _decimals, address admin, uint256 initialAmount) {
        _DECIMALS = _decimals;
        ADMIN = admin;

        _mint(admin, initialAmount);
    }

    function decimals() public view override returns (uint8) {
        return _DECIMALS;
    }

    function mint(address recipient, uint256 amount) public {
        require(msg.sender == ADMIN);
        _mint(recipient, amount);
    }
}
