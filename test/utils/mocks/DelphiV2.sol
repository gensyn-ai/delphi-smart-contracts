// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// import {Delphi} from "src/delphi/delphi/Delphi.sol";
// import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
