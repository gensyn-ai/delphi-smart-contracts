// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IOracle} from "src/IOracle.sol";
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";

contract MockOracleRelayer is IOracle {
    ILmsrGateway public immutable GATEWAY;
    mapping(address marketProxy => uint256 outcomeIdx) public pendingOutcome;
    address public oracleFeeRecipient;

    /// @dev When true, resolveMarket is a no-op: it lets gateway.resolveMarket set `settlementLocked`
    ///      without settling the market — simulating a relayer that received the request but has not yet
    ///      responded. Lets tests obtain a locked-but-still-AWAITING market via the real resolve flow.
    bool public lockOnly;

    constructor(ILmsrGateway gateway_) {
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
