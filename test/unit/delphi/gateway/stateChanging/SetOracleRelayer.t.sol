// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LmsrGateway_SetOracleRelayer_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Tests

    function testFuzz_SetOracleRelayer_CallerNotOwner_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address caller,
        address relayer
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

        // Set oracle relayer
        deployment.gateway.setOracleRelayer(relayer);
    }

    function testFuzz_SetOracleRelayer_OracleRelayerIsZeroAddress_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Switch to owner
        _useNewSender(GATEWAY_OWNER);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.OracleRelayerIsZeroAddress.selector));

        // Set oracle relayer to the zero address
        deployment.gateway.setOracleRelayer(address(0));
    }

    function testFuzz_SetOracleRelayer_OracleRelayerIsNotAContract_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address relayer
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Switch to owner
        _useNewSender(GATEWAY_OWNER);

        // Ensure relayer is not the zero address and is not a contract
        vm.assume(relayer != address(0));
        vm.assume(relayer.code.length == 0);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.OracleRelayerIsNotAContract.selector, relayer));

        // Set oracle relayer
        deployment.gateway.setOracleRelayer(relayer);
    }

    function testFuzz_SetOracleRelayer_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Record current oracle relayer
        address currentOracleRelayer = deployment.gateway.oracleRelayer();

        // Deploy new oracle relayer
        address newOracleRelayer = address(new MockOracleRelayer({gateway_: deployment.gateway}));

        // Switch to owner
        _useNewSender(GATEWAY_OWNER);

        // Expect event emission
        vm.expectEmit(true, true, true, true, address(deployment.gateway));
        emit ILmsrGateway.OracleRelayerSet(currentOracleRelayer, newOracleRelayer);

        // Set oracle relayer
        deployment.gateway.setOracleRelayer(newOracleRelayer);

        // Validate
        assertEq(deployment.gateway.oracleRelayer(), newOracleRelayer, "oracleRelayer mismatch");
    }
}
