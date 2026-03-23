// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {All_Invariants} from "./invariants/AllInvariants.t.sol";

// Handlers
import {EndToEndHandler} from "./handlers/EndToEndHandler.t.sol";
import {EndToEndHandler_Converge} from "./handlers/EndToEndHandlerConverge.t.sol";

contract Invariants_Shallow_Random is All_Invariants {
    function setUp() external {
        _setUp({handler_: new EndToEndHandler({minTradesPerMarket: 0, maxTradesPerMarket: 10, maxTraderCount: 2})});
    }
}

contract Invariants_Shallow_Converge is All_Invariants {
    function setUp() external {
        _setUp({
            handler_: new EndToEndHandler_Converge({minTradesPerMarket: 0, maxTradesPerMarket: 10, maxTraderCount: 2})
        });
    }
}

contract Invariants_Medium_Random is All_Invariants {
    function setUp() external {
        _setUp({handler_: new EndToEndHandler({minTradesPerMarket: 10, maxTradesPerMarket: 890, maxTraderCount: 25})});
    }
}

contract Invariants_Medium_Converge is All_Invariants {
    function setUp() external {
        _setUp({
            handler_: new EndToEndHandler_Converge({
                minTradesPerMarket: 10, maxTradesPerMarket: 890, maxTraderCount: 25
            })
        });
    }
}

contract Invariants_Deep_Random is All_Invariants {
    function setUp() external {
        _setUp({handler_: new EndToEndHandler({minTradesPerMarket: 890, maxTradesPerMarket: 900, maxTraderCount: 100})});
    }
}

contract Invariants_Deep_Converge is All_Invariants {
    function setUp() external {
        _setUp({
            handler_: new EndToEndHandler_Converge({
                minTradesPerMarket: 890, maxTradesPerMarket: 900, maxTraderCount: 100
            })
        });
    }
}
