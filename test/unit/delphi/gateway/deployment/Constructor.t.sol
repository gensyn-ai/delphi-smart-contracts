// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";

// Mocks
import {MockToken} from "test/support/mocks/MockToken.sol";

// Interfaces
import {ILmsrGatewayErrors} from "src/lmsr/gateway/ILmsrGatewayErrors.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract LmsrGateway_Constructor_Test is DelphiTestUtils {
    // Tests
    function testFuzz_Constructor_TokenIsZeroAddress_Reverts(address owner_) external {
        // Ensure owner is not the zero address (so the Ownable check passes)
        vm.assume(owner_ != address(0));

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.TokenIsZeroAddress.selector));

        // Deploy gateway with a zero token
        new LmsrGateway(IERC20Metadata(address(0)), owner_);
    }

    function testFuzz_Constructor_TokenIsNotAContract_Reverts(address token_, address owner_) external {
        // Ensure owner is not the zero address
        vm.assume(owner_ != address(0));

        // Ensure token is a non-zero, non-contract address
        vm.assume(token_ != address(0));
        vm.assume(token_.code.length == 0);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.TokenIsNotAContract.selector, token_));

        // Deploy gateway with a non-contract token
        new LmsrGateway(IERC20Metadata(token_), owner_);
    }

    function testFuzz_Constructor_TokenDecimalsAreTooLow_Reverts(uint8 decimals, address owner_) external {
        // Ensure owner is not the zero address
        vm.assume(owner_ != address(0));

        // Bound decimals below the minimum
        decimals = _boundUint8(decimals, 0, 5);

        // Deploy Token
        MockToken token_ = new MockToken({
            name: TOKEN_NAME, symbol: TOKEN_SYMBOL, _decimals: decimals, admin: TOKEN_ADMIN, initialAmount: 0
        });

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.TokenDecimalsAreTooLow.selector, decimals));

        // Deploy gateway
        new LmsrGateway(token_, owner_);
    }

    function testFuzz_Constructor_TokenDecimalsAreTooHigh_Reverts(uint8 decimals, address owner_) external {
        // Ensure owner is not the zero address
        vm.assume(owner_ != address(0));

        // Bound decimals above the maximum
        decimals = _boundUint8(decimals, 19, type(uint8).max);

        // Deploy Token
        MockToken token_ = new MockToken({
            name: TOKEN_NAME, symbol: TOKEN_SYMBOL, _decimals: decimals, admin: TOKEN_ADMIN, initialAmount: 0
        });

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrGatewayErrors.TokenDecimalsAreTooHigh.selector, decimals));

        // Deploy gateway
        new LmsrGateway(token_, owner_);
    }

    function testFuzz_Constructor_Success(uint8 decimals, address owner_) external {
        // Ensure owner is not the zero address
        vm.assume(owner_ != address(0));

        // Bound decimals to the valid range
        decimals = _boundUint8(decimals, 6, 18);

        // Deploy token
        MockToken token_ = _boundAndDeployToken(decimals);

        // Deploy gateway
        LmsrGateway gateway_ = new LmsrGateway(token_, owner_);

        // Validate immutables
        assertEq(address(gateway_.TOKEN()), address(token_), "TOKEN mismatch");
        assertEq(gateway_.TOKEN_DECIMAL_SCALER(), 10 ** (18 - decimals), "TOKEN_DECIMAL_SCALER mismatch");
        assertEq(gateway_.MIN_SHARES_DELTA(), 0.01e18, "MIN_SHARES_DELTA mismatch");
        assertEq(gateway_.owner(), owner_, "owner mismatch");
    }
}
