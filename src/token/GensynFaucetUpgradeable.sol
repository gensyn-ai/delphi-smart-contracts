// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {GensynFaucetStorage} from "./GensynFaucetStorage.sol";

contract GensynFaucetUpgradeable is GensynFaucetStorage, UUPSUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public immutable GENSYN_TOKEN;
    bytes32 public constant DRIP_MANAGER_ROLE = keccak256("DRIP_MANAGER_ROLE");

    event DripTimeUpdated(uint256 oldDrip, uint256 newDrip);
    event DripAmountUpdated(uint256 oldDelay, uint256 newDelay);

    error RequestTooOften();

    constructor(address gensynTokenProxy) {
        require(address(gensynTokenProxy) != address(0), "token address should not be address(0)");

        GENSYN_TOKEN = IERC20(gensynTokenProxy);
        _disableInitializers();
    }

    function initialize(address admin, address dripManager, uint256 _dripTime, uint256 _dripAmount)
        external
        initializer
    {
        GensynFaucetData storage $ = _getGensynFaucetStorage();

        // __AccessControl_init();

        require(admin != address(0), "admin should not be address(0)");
        require(dripManager != address(0), "dripManager should not be address(0)");

        $.dripTime = _dripTime;
        $.dripAmount = _dripAmount;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DRIP_MANAGER_ROLE, dripManager);
    }

    function requestToken() external {
        GensynFaucetData storage $ = _getGensynFaucetStorage();

        require($.lastRequested[msg.sender] + $.dripTime < block.timestamp, RequestTooOften());
        $.lastRequested[msg.sender] = block.timestamp;

        GENSYN_TOKEN.safeTransfer(msg.sender, $.dripAmount);
    }

    function setDripTime(uint256 _dripTime) external onlyRole(DRIP_MANAGER_ROLE) {
        GensynFaucetData storage $ = _getGensynFaucetStorage();

        uint256 oldDripTime = $.dripTime;
        $.dripTime = _dripTime;
        emit DripTimeUpdated(oldDripTime, _dripTime);
    }

    function setDripAmount(uint256 _dripAmount) external onlyRole(DRIP_MANAGER_ROLE) {
        GensynFaucetData storage $ = _getGensynFaucetStorage();

        uint256 oldDripAmount = $.dripAmount;
        $.dripAmount = _dripAmount;
        emit DripAmountUpdated(oldDripAmount, _dripAmount);
    }

    function getDripTime() external view returns (uint256) {
        return _getGensynFaucetStorage().dripTime;
    }

    function getDripAmount() external view returns (uint256) {
        return _getGensynFaucetStorage().dripAmount;
    }

    function getLastRequested(address user) external view returns (uint256) {
        return _getGensynFaucetStorage().lastRequested[user];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
