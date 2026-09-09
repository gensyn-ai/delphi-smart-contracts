// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {IDelphiFactory} from "src/factory/IDelphiFactory.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

contract LmsrGateway_Initialize_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Functions

    /// @dev Deploys the full system, then a fresh uninitialized gateway whose deployer is this test contract.
    function _freshGateway(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) internal returns (LmsrGateway) {
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });
        vm.stopPrank();
        return new LmsrGateway(token, GATEWAY_OWNER);
    }

    // Tests

    function testFuzz_Initialize_InitializerNotDeployer_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address caller
    ) external {
        // Deploy a fresh gateway (deployer is this test contract)
        LmsrGateway freshGateway = _freshGateway(tokenDecimals, delphiConfig, marketConfig, initialDeposit);

        // Ensure caller is not the deployer
        vm.assume(caller != address(this));

        // Switch to caller
        _useNewSender(caller);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrGatewayErrors.InitializerNotDeployer.selector, caller, address(this))
        );

        // Initialize
        freshGateway.initialize(deployment.factory);
    }

    function testFuzz_Initialize_DelphiFactoryIsZeroAddress_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) external {
        // Deploy a fresh gateway (deployer is this test contract)
        LmsrGateway freshGateway = _freshGateway(tokenDecimals, delphiConfig, marketConfig, initialDeposit);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.DelphiFactoryIsZeroAddress.selector));

        // Initialize with a zero factory
        freshGateway.initialize(IDelphiFactory(address(0)));
    }

    function testFuzz_Initialize_DelphiFactoryIsNotContract_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address fakeFactory
    ) external {
        // Deploy a fresh gateway (deployer is this test contract)
        LmsrGateway freshGateway = _freshGateway(tokenDecimals, delphiConfig, marketConfig, initialDeposit);

        // Ensure the fake factory is a non-zero, non-contract address
        vm.assume(fakeFactory != address(0));
        vm.assume(fakeFactory.code.length == 0);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.DelphiFactoryIsNotContract.selector, fakeFactory));

        // Initialize with a non-contract factory
        freshGateway.initialize(IDelphiFactory(fakeFactory));
    }

    function testFuzz_Initialize_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) external {
        // Deploy a fresh gateway (deployer is this test contract)
        LmsrGateway freshGateway = _freshGateway(tokenDecimals, delphiConfig, marketConfig, initialDeposit);

        // Initialize with the real factory
        freshGateway.initialize(deployment.factory);

        // Validate
        assertEq(address(freshGateway.delphiFactory()), address(deployment.factory), "delphiFactory mismatch");
    }
}
