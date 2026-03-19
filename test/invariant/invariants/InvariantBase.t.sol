// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {BaseTest} from "test/utils/BaseTest.t.sol";

// Contracts
import {IEndToEndHandler} from "../handlers/IEndToEndHandler.sol";

abstract contract Invariants_Base is BaseTest {
    // State variables
    IEndToEndHandler handler;

    modifier ifDeployed() {
        if (handler.deployed()) {
            _;
        }
    }

    function _setUp(IEndToEndHandler handler_) internal {
        // // Deploy Handler
        // handler = new EndToEndHandler(minTradesPerMarket, maxTradesPerMarket);
        handler = handler_;

        // Label Handler
        vm.label({account: address(handler), newLabel: "Handler"});

        // Target balance sheet contract for invariant tests
        targetContract(address(handler));

        // Target step function for invariant tests
        bytes4[] memory includedSelectors = new bytes4[](1);
        includedSelectors[0] = IEndToEndHandler.step.selector;
        targetSelector({newTargetedSelector_: FuzzSelector({addr: address(handler), selectors: includedSelectors})});
    }
}
