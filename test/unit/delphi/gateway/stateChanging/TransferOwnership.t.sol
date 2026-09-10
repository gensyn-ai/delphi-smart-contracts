// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract LmsrGateway_TransferOwnership_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests

    function testFuzz_TransferOwnership_CallerIsNotOwner_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address caller,
        address newOwner
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure caller is not the owner
        vm.assume(caller != GATEWAY_OWNER);

        // Switch to caller
        _useNewSender(caller);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        // Transfer ownership
        deployment.gateway.transferOwnership(newOwner);
    }

    function testFuzz_AcceptOwnership_CallerIsNotPendingOwner_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address newOwner,
        address caller
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure caller is not the pending owner
        vm.assume(caller != newOwner);

        // Switch to owner
        _useNewSender(GATEWAY_OWNER);

        // Transfer ownership
        deployment.gateway.transferOwnership(newOwner);

        // Switch to caller
        _useNewSender(caller);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));

        // Accept ownership
        deployment.gateway.acceptOwnership();
    }

    function testFuzz_TransferOwnership_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address newOwner
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Ensure new owner is a usable address
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != GATEWAY_OWNER);

        // Switch to owner
        _useNewSender(GATEWAY_OWNER);

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit Ownable2Step.OwnershipTransferStarted(GATEWAY_OWNER, newOwner);

        // Transfer ownership (step 1: owner is unchanged, new owner is pending)
        deployment.gateway.transferOwnership(newOwner);

        // Validate
        assertEq(deployment.gateway.owner(), GATEWAY_OWNER, "owner changed before acceptance");
        assertEq(deployment.gateway.pendingOwner(), newOwner, "pendingOwner mismatch");

        // Switch to new owner
        _useNewSender(newOwner);

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit Ownable.OwnershipTransferred(GATEWAY_OWNER, newOwner);

        // Accept ownership (step 2: ownership actually transfers)
        deployment.gateway.acceptOwnership();

        // Validate
        assertEq(deployment.gateway.owner(), newOwner, "owner mismatch");
        assertEq(deployment.gateway.pendingOwner(), address(0), "pendingOwner not cleared");
    }
}
