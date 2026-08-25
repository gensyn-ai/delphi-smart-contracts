// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOracle {
    function resolveMarket(address marketProxy) external;
}
