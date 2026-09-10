// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

abstract contract DelphiV2 {
    /* is Delphi */
    uint256 public foo;
    uint256 public bar;

    // constructor(address marketCreator, IERC20Metadata token) Delphi(marketCreator, token) {}

    function setFoo(uint256 newFoo) external {
        foo = newFoo;
    }

    function setBar(uint256 newBar) external {
        bar = newBar;
    }

    function version() external view virtual returns (uint256) {
        return 2;
    }
}
