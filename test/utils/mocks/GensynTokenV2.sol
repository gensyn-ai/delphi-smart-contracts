// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestToken} from "src/token/TestToken.sol";

contract GensynTokenV2 is TestToken {
    uint256 public foo;
    uint256 public bar;

    function setFoo(uint256 newFoo) external {
        foo = newFoo;
    }

    function setBar(uint256 newBar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bar = newBar;
    }

    function version() external view virtual returns (uint256) {
        return 2;
    }
}
