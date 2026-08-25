// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOracle} from "src/delphi/IOracle.sol";
import {IDynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGateway.sol";

contract MockOracleRelayer is IOracle {
    IDynamicParimutuelGateway public immutable GATEWAY;
    mapping(address marketProxy => uint256 outcomeIdx) public pendingOutcome;
    address public oracleFeeRecipient;

    /// @dev When true, resolveMarket is a no-op: it lets gateway.resolveMarket set `settlementLocked`
    ///      without settling the market — simulating a relayer that received the request but has not yet
    ///      responded. Lets tests obtain a locked-but-still-AWAITING market via the real resolve flow.
    bool public lockOnly;

    constructor(IDynamicParimutuelGateway gateway_) {
        GATEWAY = gateway_;
    }

    function setOutcome(address marketProxy, uint256 outcomeIdx) external {
        pendingOutcome[marketProxy] = outcomeIdx;
    }

    function setOracleFeeRecipient(address recipient) external {
        oracleFeeRecipient = recipient;
    }

    function setLockOnly(bool lockOnly_) external {
        lockOnly = lockOnly_;
    }

    function resolveMarket(address marketProxy) external {
        if (lockOnly) return;
        GATEWAY.settleMarket(marketProxy, pendingOutcome[marketProxy], oracleFeeRecipient);
    }
}
