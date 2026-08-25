// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "../utils/DelphiTestUtils.t.sol";
import {DelphiDeployer} from "script/utils/deployer/DelphiDeployer.sol";

// Contracts
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";
import {DynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/DynamicParimutuelMarket.sol";
import {IEndToEndHandler} from "../invariant/handlers/IEndToEndHandler.sol";
import {DynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/DynamicParimutuelGateway.sol";
import {MockToken} from "src/mock/MockToken.sol";
import {MockOracleRelayer} from "test/mocks/MockOracleRelayer.sol";
import {IOracle} from "src/delphi/IOracle.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Interfaces
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDelphiFactory} from "src/delphi/factory/IDelphiFactory.sol";
import {IDelphiFactoryErrors} from "src/delphi/factory/IDelphiFactoryErrors.sol";
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";
import {
    IDynamicParimutuelMarketErrors
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketErrors.sol";
import {IDynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGateway.sol";
import {
    IDynamicParimutuelGatewayErrors
} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGatewayErrors.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract DelphiUnit_Test is DelphiTestUtils, DelphiDeployer {
    // Constants
    address immutable GENSYN = makeAddr("GENSYN");
    address immutable CREATOR = makeAddr("CREATOR");
    address immutable USER = makeAddr("USER");

    // State Variables
    IERC20Metadata token;
    DelphiFactory delphiFactory;
    DynamicParimutuelMarket implementation;
    DynamicParimutuelGateway gateway;
    MockOracleRelayer mockOracleRelayer;

    function _setUp(
        uint8 decimals,
        uint256 /*marketCreationFee*/
    )
        internal
        returns (uint8)
    {
        decimals = _deployStack(decimals);

        // Wire an oracle relayer before any market is created — markets now require one at init.
        mockOracleRelayer = new MockOracleRelayer(gateway);
        gateway.setOracleRelayer(address(mockOracleRelayer));

        return decimals;
    }

    /// @dev Deploys the token + Delphi stack but does NOT wire an oracle relayer. `_setUp` adds the relayer
    ///      on top; tests that need the no-relayer state (the deployment-race guard, the first-ever
    ///      setOracleRelayer) call this directly. Leaves the active sender as GENSYN (the gateway owner).
    function _deployStack(uint8 decimals) private returns (uint8) {
        decimals = _boundUint8(decimals, 6, 18);

        _useNewSender(GENSYN);
        token = new MockToken({name: "MockToken", symbol: "MOCK", _decimals: decimals, admin: GENSYN, initialAmount: 0});

        // Deploy All
        DelphiAddresses memory deployment = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: GENSYN,
                marketCreationFeeRecipient: GENSYN,
                marketCreationFee: 0,
                keeperFee: 0,
                oracleFee: 0,
                tradingFeesRecipientPct: 0.1e18,
                token: token,
                gatewayOwner: GENSYN
            })
        );

        delphiFactory = deployment.delphiFactory;
        implementation = deployment.dynamicParimutuelImplementation;
        gateway = deployment.dynamicParimutuelGateway;

        return decimals;
    }

    // ======== FACTORY DEPLOYMENT ========

    function test_DeployFactory_Reverts_OnlyDeployerCanInitialize(uint8 decimals) external {
        _useNewSender(GENSYN);

        decimals = _boundUint8(decimals, 6, 18);
        IERC20Metadata _token =
            new MockToken({name: "MockToken", symbol: "MOCK", _decimals: decimals, admin: GENSYN, initialAmount: 0});
        DynamicParimutuelGateway _dynamicParimutuelGateway = new DynamicParimutuelGateway(_token, GENSYN);

        // Deploy DynamicParimutuel Implementation
        DynamicParimutuelMarket _dynamicParimutuelImplementation = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_dynamicParimutuelGateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: 0,
            oracleFee: 0
        });

        // Deploy DelphiFactory implementation
        DelphiFactory _delphiFactory = new DelphiFactory({
            implementation: address(_dynamicParimutuelImplementation),
            marketCreationFee: 0,
            marketCreationFeeRecipient: GENSYN
        });

        // Initialize Gateway
        _useNewSender(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IDynamicParimutuelGatewayErrors.InitializerNotDeployer.selector, USER, GENSYN)
        );
        _dynamicParimutuelGateway.initialize({delphiFactory_: _delphiFactory});
    }

    function test_DeployFactory_Reverts_CannotInitializeWithAddressZero(uint8 decimals) external {
        _useNewSender(GENSYN);

        token = new MockToken({
            name: "MockToken", symbol: "MOCK", _decimals: _boundUint8(decimals, 6, 18), admin: GENSYN, initialAmount: 0
        });

        DynamicParimutuelGateway _dynamicParimutuelGateway = new DynamicParimutuelGateway(token, GENSYN);

        // Initialize Gateway
        vm.expectRevert(abi.encodeWithSelector(IDynamicParimutuelGatewayErrors.DelphiFactoryIsZeroAddress.selector));
        _dynamicParimutuelGateway.initialize({delphiFactory_: IDelphiFactory(address(0))});
    }

    function test_DeployFactory_Reverts_CannotInitializeTwice(uint8 decimals) external {
        _setUp(decimals, 0);

        _useNewSender(GENSYN);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        gateway.initialize({delphiFactory_: delphiFactory});
    }

    function test_DeployFactory_Success(uint8 decimals) external {
        _setUp(decimals, 0);

        assertEq(delphiFactory.IMPLEMENTATION(), address(implementation), "factory does not point to implementation");
        assertEq(implementation.GATEWAY(), address(gateway), "implementation does not point to gateway");
        assertEq(address(gateway.delphiFactory()), address(delphiFactory), "gateway does not point to factory");
    }

    // ======== MARKET CREATION ========

    function test_CreateMarket_Reverts_RandomCalldata(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args,
        bytes calldata randomCalldata
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        vm.expectRevert();
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: randomCalldata
        });
    }

    function test_CreateMarket_Reverts_FailedTokenTransfer(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, delphiFactory, 0, args.initialDeposit
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_ModelCountTooLow(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.outcomeCount =
            bound(args.newMarketConfig.outcomeCount, 0, implementation.MIN_OUTCOME_COUNT() - 1);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.OutcomeCountTooLow.selector,
                args.newMarketConfig.outcomeCount,
                implementation.MIN_OUTCOME_COUNT()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_ModelCountTooHigh(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.outcomeCount =
            bound(args.newMarketConfig.outcomeCount, implementation.MAX_OUTCOME_COUNT() + 1, type(uint256).max);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.OutcomeCountTooHigh.selector,
                args.newMarketConfig.outcomeCount,
                implementation.MAX_OUTCOME_COUNT()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_KTooLow(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.k = bound(args.newMarketConfig.k, 0, implementation.MIN_K() - 1);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.KTooLow.selector, args.newMarketConfig.k, implementation.MIN_K()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_KTooHigh(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.k = bound(args.newMarketConfig.k, implementation.MAX_K() + 1, type(uint256).max);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.KTooHigh.selector, args.newMarketConfig.k, implementation.MAX_K()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_TradingFeeTooLow(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.tradingFee =
            bound(args.newMarketConfig.tradingFee, 0, implementation.MIN_TRADING_FEE() - 1);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingFeeTooLow.selector,
                args.newMarketConfig.tradingFee,
                implementation.MIN_TRADING_FEE()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_TradingFeeTooHigh(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.tradingFee =
            bound(args.newMarketConfig.tradingFee, implementation.MAX_TRADING_FEE() + 1, type(uint256).max);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingFeeTooHigh.selector,
                args.newMarketConfig.tradingFee,
                implementation.MAX_TRADING_FEE()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_TradingDeadlineNotInFuture(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.tradingDeadline = bound(args.newMarketConfig.tradingDeadline, 0, block.timestamp);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingDeadlineNotInFuture.selector,
                args.newMarketConfig.tradingDeadline,
                block.timestamp
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_TradingWindowTooShort(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.tradingDeadline = bound(
            args.newMarketConfig.tradingDeadline,
            block.timestamp + 1,
            block.timestamp + implementation.MIN_TRADING_WINDOW() - 1
        );

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingWindowTooShort.selector,
                args.newMarketConfig.tradingDeadline - block.timestamp,
                implementation.MIN_TRADING_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_TradingWindowTooLong(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.tradingDeadline = bound(
            args.newMarketConfig.tradingDeadline,
            block.timestamp + implementation.MAX_TRADING_WINDOW() + 1,
            type(uint256).max
        );

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingWindowTooLong.selector,
                args.newMarketConfig.tradingDeadline - block.timestamp,
                implementation.MAX_TRADING_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_SettlementDeadlineTooLong(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.settlementDeadline =
            bound(args.newMarketConfig.settlementDeadline, 0, args.newMarketConfig.tradingDeadline);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.SettlementDeadlineBeforeTradingDeadline.selector,
                args.newMarketConfig.settlementDeadline,
                args.newMarketConfig.tradingDeadline
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_SettlementWindowTooShort(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.settlementDeadline = bound(
            args.newMarketConfig.settlementDeadline,
            args.newMarketConfig.tradingDeadline + 1,
            args.newMarketConfig.tradingDeadline + implementation.MIN_SETTLEMENT_WINDOW() - 1
        );

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.SettlementWindowTooShort.selector,
                args.newMarketConfig.settlementDeadline - args.newMarketConfig.tradingDeadline,
                implementation.MIN_SETTLEMENT_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_SettlementWindowTooLong(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketConfig.settlementDeadline = bound(
            args.newMarketConfig.settlementDeadline,
            args.newMarketConfig.tradingDeadline + implementation.MAX_SETTLEMENT_WINDOW() + 1,
            type(uint256).max
        );

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.SettlementWindowTooLong.selector,
                args.newMarketConfig.settlementDeadline - args.newMarketConfig.tradingDeadline,
                implementation.MAX_SETTLEMENT_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_UriEmpty(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketMetadata.uri = "";

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(IDynamicParimutuelMarketErrors.EmptyUri.selector);
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_UriContentHashEmpty(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.newMarketMetadata.uriContentHash = bytes32(0);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(IDynamicParimutuelMarketErrors.EmptyUriContentHash.selector);
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_InitialDepositTooLow(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.initialDeposit = bound(args.initialDeposit, 0, implementation.MIN_INITIAL_DEPOSIT() - 1);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.InitialDepositTooLow.selector,
                args.initialDeposit,
                implementation.MIN_INITIAL_DEPOSIT()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_InitialDepositTooHigh(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.initialDeposit = bound(args.initialDeposit, implementation.MAX_INITIAL_DEPOSIT() + 1, type(uint256).max);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.InitialDepositTooHigh.selector,
                args.initialDeposit,
                implementation.MAX_INITIAL_DEPOSIT()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Success(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        delphiFactory.deployNewMarketProxy({
            initialDeposit_: args.initialDeposit,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });

        // TODO asserts
    }

    // ======== GATEWAY MIN DELTAS ========

    function test_Gateway_MinTokensDelta(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        uint256 tokenDecimalScaler = 10 ** (18 - decimals);
        uint256 expectedMinTokensDelta = 0.01e18 / tokenDecimalScaler;

        assertEqDecimal(
            gateway.MIN_TOKENS_DELTA(), // left
            expectedMinTokensDelta, // right
            decimals,
            "minTokensDelta mismatch for token decimals"
        );
    }

    function _setUpMarket() private returns (IDynamicParimutuelMarket marketProxy) {
        _setUp(6, 0);
        _useNewSender(CREATOR);

        uint256 initialDeposit = implementation.MIN_INITIAL_DEPOSIT();
        uint256 minTradingWindow = implementation.MIN_TRADING_WINDOW();

        IDynamicParimutuelMarketTypes.MarketConfig memory config = IDynamicParimutuelMarketTypes.MarketConfig({
            outcomeCount: implementation.MIN_OUTCOME_COUNT(),
            k: implementation.MIN_K(),
            tradingFee: implementation.MIN_TRADING_FEE(),
            tradingDeadline: block.timestamp + minTradingWindow,
            settlementDeadline: block.timestamp + minTradingWindow + implementation.MIN_SETTLEMENT_WINDOW()
        });

        deal(address(token), CREATOR, initialDeposit);
        token.approve(address(delphiFactory), initialDeposit);

        marketProxy = IDynamicParimutuelMarket(
            delphiFactory.deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
                newMarketInitializationCalldata_: abi.encode(config)
            })
        );
    }

    function test_Gateway_Reverts_SharesOutBelowMinDelta() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        uint256 minSharesDelta = gateway.MIN_SHARES_DELTA();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.SharesOutBelowMinDelta.selector, minSharesDelta - 1, minSharesDelta
            )
        );
        gateway.quoteBuyExactOut(marketProxy, 0, minSharesDelta - 1);
    }

    function test_Gateway_Reverts_SharesInBelowMinDelta() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        uint256 minSharesDelta = gateway.MIN_SHARES_DELTA();

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.SharesInBelowMinDelta.selector, minSharesDelta - 1, minSharesDelta
            )
        );
        gateway.quoteSellExactIn(marketProxy, 0, minSharesDelta - 1);
    }

    function test_Gateway_Reverts_OutcomeSupplyBelowMinDelta() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        uint256 minSharesDelta = gateway.MIN_SHARES_DELTA();
        uint256 totalSupply0 = marketProxy.totalSupply(0);

        // Selling (totalSupply0 - 1) shares leaves supply = 1, which is in (0, MIN_SHARES_DELTA)
        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.OutcomeSupplyBelowMinDelta.selector, 1, minSharesDelta
            )
        );
        gateway.quoteSellExactIn(marketProxy, 0, totalSupply0 - 1);
    }

    function test_Gateway_Reverts_TokensInBelowMin() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        uint256 minSharesDelta = gateway.MIN_SHARES_DELTA();

        // With MIN_K and MIN_INITIAL_DEPOSIT, buying MIN_SHARES_DELTA shares
        // produces tokensIn well below minTokensDelta (1e4 for 6 decimals)
        vm.expectPartialRevert(IDynamicParimutuelGatewayErrors.TokensInBelowMin.selector);
        gateway.quoteBuyExactOut(marketProxy, 0, minSharesDelta);
    }

    function test_Gateway_Reverts_TokensOutBelowMin() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        uint256 minSharesDelta = gateway.MIN_SHARES_DELTA();

        // With MIN_K and MIN_INITIAL_DEPOSIT, selling a small amount of shares
        // produces tokensOut below minTokensDelta (1e4 for 6 decimals).
        // We use minSharesDelta * 1e8 so grossTokensOut > 0 but still below minTokensDelta.
        uint256 sharesToSell = minSharesDelta * 1e8;
        vm.expectPartialRevert(IDynamicParimutuelGatewayErrors.TokensOutBelowMin.selector);
        gateway.quoteSellExactIn(marketProxy, 0, sharesToSell);
    }

    // ======== DEPLOYMENT ========

    function test_Deploy_Reverts_TradingFeesRecipientPctTooHigh(
        uint8 decimals,
        uint256 marketCreationFee,
        uint256 tradingFeesRecipientPct
    ) external {
        decimals = _setUp(decimals, marketCreationFee);

        tradingFeesRecipientPct =
            bound(tradingFeesRecipientPct, implementation.MAX_TRADING_FEES_RECIPIENT_PCT() + 1, type(uint256).max);

        DynamicParimutuelGateway newGateway = new DynamicParimutuelGateway(token, GENSYN);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingFeesRecipientPctTooHigh.selector,
                tradingFeesRecipientPct,
                implementation.MAX_TRADING_FEES_RECIPIENT_PCT()
            )
        );
        new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(newGateway),
            tradingFeesRecipientPct: tradingFeesRecipientPct,
            keeperFee: 0,
            oracleFee: 0
        });
    }

    function test_Deploy_Reverts_MarketCreationFeeTooHigh(uint8 decimals, uint256 marketCreationFee) external {
        decimals = _setUp(decimals, marketCreationFee);

        uint256 maxMarketCreationFee = delphiFactory.MAX_MARKET_CREATION_FEE();
        marketCreationFee = bound(marketCreationFee, maxMarketCreationFee + 1, type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDelphiFactoryErrors.MarketCreationFeeTooHigh.selector, marketCreationFee, maxMarketCreationFee
            )
        );
        new DelphiFactory({
            implementation: address(implementation),
            marketCreationFee: marketCreationFee,
            marketCreationFeeRecipient: GENSYN
        });
    }

    // ======== GATEWAY SETTLEMENT ========

    function _setUpMarketAwaitingSettlement() private returns (IDynamicParimutuelMarket marketProxy) {
        // The oracle relayer is already wired in _setUp (called by _setUpMarket).
        marketProxy = _setUpMarket();
        // Warp past the trading deadline so market status becomes AWAITING_SETTLEMENT
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);
    }

    /// @dev A market cannot be created before the gateway has an oracle relayer wired.
    ///      This closes the deployment race atomically at creation (the market would otherwise be
    ///      un-resolvable and could only expire). Replaces the old resolveMarket-time test, whose
    ///      scenario is now unreachable for a factory market (creation requires a relayer, and the
    ///      relayer can never be reset to address(0)).
    function test_CreateMarket_Reverts_OracleRelayerNotSet() external {
        // Deploy the stack but deliberately do NOT wire an oracle relayer.
        _deployStack(6);

        uint256 initialDeposit = implementation.MIN_INITIAL_DEPOSIT();
        uint256 minTradingWindow = implementation.MIN_TRADING_WINDOW();
        IDynamicParimutuelMarketTypes.MarketConfig memory config = IDynamicParimutuelMarketTypes.MarketConfig({
            outcomeCount: implementation.MIN_OUTCOME_COUNT(),
            k: implementation.MIN_K(),
            tradingFee: implementation.MIN_TRADING_FEE(),
            tradingDeadline: block.timestamp + minTradingWindow,
            settlementDeadline: block.timestamp + minTradingWindow + implementation.MIN_SETTLEMENT_WINDOW()
        });

        _useNewSender(CREATOR);
        deal(address(token), CREATOR, initialDeposit);
        token.approve(address(delphiFactory), initialDeposit);

        vm.expectRevert(IDynamicParimutuelMarketErrors.GatewayOracleRelayerNotSet.selector);
        delphiFactory.deployNewMarketProxy({
            initialDeposit_: initialDeposit,
            newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
            newMarketInitializationCalldata_: abi.encode(config)
        });
    }

    function test_ResolveMarket_Reverts_SettlementAlreadyLocked() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        mockOracleRelayer.setOutcome(address(marketProxy), 0);
        gateway.resolveMarket(address(marketProxy));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.SettlementAlreadyLocked.selector, address(marketProxy)
            )
        );
        gateway.resolveMarket(address(marketProxy));
    }

    function test_ResolveMarket_Success_Permissionless(address caller) external {
        vm.assume(caller != address(0));

        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.AWAITING_SETTLEMENT),
            "market should be AWAITING_SETTLEMENT"
        );

        mockOracleRelayer.setOutcome(address(marketProxy), 0);

        _useNewSender(caller);
        gateway.resolveMarket(address(marketProxy));

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.SETTLED),
            "market should be SETTLED after resolution"
        );
        assertTrue(gateway.settlementLocked(address(marketProxy)), "lock should stay true after settlement");
    }

    function test_ResolveMarket_EmitsMarketResolutionRequested(address keeper) external {
        vm.assume(keeper != address(0));

        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        mockOracleRelayer.setOutcome(address(marketProxy), 0);

        vm.expectEmit(true, true, false, false, address(gateway));
        emit IDynamicParimutuelGateway.MarketResolutionRequested(address(marketProxy), keeper);

        _useNewSender(keeper);
        gateway.resolveMarket(address(marketProxy));
    }

    function test_ResolveMarket_Reverts_NotDeployedByFactory(address randomProxy) external {
        _setUp(6, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.MarketProxyNotDeployedByFactory.selector, randomProxy
            )
        );
        gateway.resolveMarket(randomProxy);
    }

    function test_SettleMarket_Reverts_NotOracleRelayer(address caller) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.assume(caller != address(mockOracleRelayer));
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(IDynamicParimutuelGatewayErrors.NotOracleRelayer.selector, caller));
        gateway.settleMarket(address(marketProxy), 0, address(0));
    }

    function test_SettleMarket_Reverts_NotLocked() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        // No resolveMarket → settlementLocked is false. Even the registered relayer cannot settle.
        _useNewSender(address(mockOracleRelayer));
        vm.expectRevert(
            abi.encodeWithSelector(IDynamicParimutuelGatewayErrors.SettlementNotLocked.selector, address(marketProxy))
        );
        gateway.settleMarket(address(marketProxy), 0, address(0));
    }

    function test_SettleMarket_Reverts_NotDeployedByFactory(address randomProxy) external {
        _setUp(6, 0);

        address relayer = makeAddr("relayer");
        gateway.setOracleRelayer(relayer);

        _useNewSender(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.MarketProxyNotDeployedByFactory.selector, randomProxy
            )
        );
        gateway.settleMarket(randomProxy, 0, address(0));
    }

    function test_SettleMarket_Success(uint8 winningOutcomeIdx) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        winningOutcomeIdx = uint8(bound(winningOutcomeIdx, 0, implementation.MIN_OUTCOME_COUNT() - 1));

        // Expected financial breakdown the gateway forwards from market.settleMarket. Computed from the
        // pre-settle state (same state settleMarket reads). No trades occur in _setUpMarketAwaitingSettlement,
        // so trading fees — and therefore the creator's cut — are zero.
        uint256 expectedReward = marketProxy.marketCreatorWinningSharesSettlementValue(winningOutcomeIdx);
        uint256 expectedRefund = marketProxy.getMarket().refund;
        uint256 expectedTradingFeesCut = 0;

        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        vm.expectEmit(true, false, false, true, address(gateway));
        emit IDynamicParimutuelGateway.GatewayMarketSettled(
            address(marketProxy), winningOutcomeIdx, expectedReward, expectedRefund, expectedTradingFeesCut
        );

        _useNewSender(address(mockOracleRelayer));
        gateway.settleMarket(address(marketProxy), winningOutcomeIdx, address(0));

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.SETTLED),
            "market should be SETTLED"
        );
        assertTrue(gateway.settlementLocked(address(marketProxy)), "settlement stays locked after settle");
    }

    // ======== FAIL MARKET ========

    function test_FailMarket_Reverts_NotOracleRelayer(address caller) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.assume(caller != address(mockOracleRelayer));
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(IDynamicParimutuelGatewayErrors.NotOracleRelayer.selector, caller));
        gateway.failMarket(address(marketProxy));
    }

    function test_FailMarket_Reverts_NotLocked() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        // No resolveMarket → settlementLocked is false. Even the registered relayer cannot fail.
        _useNewSender(address(mockOracleRelayer));
        vm.expectRevert(
            abi.encodeWithSelector(IDynamicParimutuelGatewayErrors.SettlementNotLocked.selector, address(marketProxy))
        );
        gateway.failMarket(address(marketProxy));
    }

    function test_FailMarket_Reverts_NotDeployedByFactory(address randomProxy) external {
        _setUp(6, 0);

        address relayer = makeAddr("relayer");
        gateway.setOracleRelayer(relayer);

        _useNewSender(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.MarketProxyNotDeployedByFactory.selector, randomProxy
            )
        );
        gateway.failMarket(randomProxy);
    }

    function test_FailMarket_Reverts_WrongMarketStatus() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        // Settle the market first so it's no longer AWAITING_SETTLEMENT
        _useNewSender(address(mockOracleRelayer));
        gateway.settleMarket(address(marketProxy), 0, address(0));

        // Lock is set, so failMarket clears the gateway guard and hits the market's status guard.
        vm.expectPartialRevert(IDynamicParimutuelMarketErrors.WrongMarketStatus.selector);
        gateway.failMarket(address(marketProxy));
    }

    function test_FailMarket_Success() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        vm.expectEmit(true, false, false, false, address(gateway));
        emit IDynamicParimutuelGateway.GatewayMarketFailed(address(marketProxy));

        _useNewSender(address(mockOracleRelayer));
        gateway.failMarket(address(marketProxy));

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.FAILED),
            "market should be FAILED"
        );
    }

    function test_FailMarket_Reverts_WrongMarketStatus_OPEN() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        // Warp back to before trading deadline so market is OPEN
        vm.warp(marketProxy.getMarket().config.tradingDeadline - 1);
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.OPEN),
            "market should be OPEN"
        );

        // Lock is set, so the revert comes from the market's status guard, not the gateway lock guard.
        _useNewSender(address(mockOracleRelayer));
        vm.expectPartialRevert(IDynamicParimutuelMarketErrors.WrongMarketStatus.selector);
        gateway.failMarket(address(marketProxy));
    }

    function test_FailMarket_Reverts_WrongMarketStatus_EXPIRED() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        // Warp past settlement deadline so market is EXPIRED
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.EXPIRED),
            "market should be EXPIRED"
        );

        // Lock is set, so the revert comes from the market's status guard, not the gateway lock guard.
        _useNewSender(address(mockOracleRelayer));
        vm.expectPartialRevert(IDynamicParimutuelMarketErrors.WrongMarketStatus.selector);
        gateway.failMarket(address(marketProxy));
    }

    function test_FailMarket_Reverts_AlreadyFailed() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        _useNewSender(address(mockOracleRelayer));
        gateway.failMarket(address(marketProxy));

        // Second call: lock is still set (permanent), so it clears the gateway guard and hits the
        // market's status guard — market is now FAILED, not AWAITING_SETTLEMENT.
        vm.expectPartialRevert(IDynamicParimutuelMarketErrors.WrongMarketStatus.selector);
        gateway.failMarket(address(marketProxy));
    }

    function test_FailMarket_LiquidationAllowedAfterFail() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        // Fail the market
        _useNewSender(address(mockOracleRelayer));
        gateway.failMarket(address(marketProxy));

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.FAILED),
            "market should be FAILED"
        );

        // Liquidation should work on FAILED market
        _useNewSender(CREATOR);
        gateway.liquidateMarketCreationShares(marketProxy);

        assertTrue(marketProxy.marketCreationSharesLiquidated(), "market creation shares should be liquidated");
    }

    // ======== LIQUIDATION STATUS GUARDS ========

    function test_Liquidate_Reverts_NotLiquidatable_WhenOpen() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket(); // market is OPEN

        uint256[] memory outcomeIndices = new uint256[](1);
        outcomeIndices[0] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.MarketNotLiquidatable.selector,
                IDynamicParimutuelMarketTypes.MarketStatus.OPEN
            )
        );
        gateway.liquidate(marketProxy, outcomeIndices);
    }

    function test_Liquidate_Reverts_NotLiquidatable_WhenSettled() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        mockOracleRelayer.setOutcome(address(marketProxy), 0);
        gateway.resolveMarket(address(marketProxy)); // market is now SETTLED

        uint256[] memory outcomeIndices = new uint256[](1);
        outcomeIndices[0] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.MarketNotLiquidatable.selector,
                IDynamicParimutuelMarketTypes.MarketStatus.SETTLED
            )
        );
        gateway.liquidate(marketProxy, outcomeIndices);
    }

    function test_LiquidateMarketCreationShares_Reverts_NotLiquidatable_WhenOpen() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket(); // market is OPEN

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.MarketNotLiquidatable.selector,
                IDynamicParimutuelMarketTypes.MarketStatus.OPEN
            )
        );
        gateway.liquidateMarketCreationShares(marketProxy);
    }

    function test_LiquidateMarketCreationShares_Reverts_NotLiquidatable_WhenSettled() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        mockOracleRelayer.setOutcome(address(marketProxy), 0);
        gateway.resolveMarket(address(marketProxy)); // market is now SETTLED

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.MarketNotLiquidatable.selector,
                IDynamicParimutuelMarketTypes.MarketStatus.SETTLED
            )
        );
        gateway.liquidateMarketCreationShares(marketProxy);
    }

    function test_LiquidateMarketCreationShares_Reverts_AlreadyLiquidated() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        // Fail the market so liquidation is allowed
        _useNewSender(address(mockOracleRelayer));
        gateway.failMarket(address(marketProxy));

        // First liquidation succeeds
        gateway.liquidateMarketCreationShares(marketProxy);
        assertTrue(marketProxy.marketCreationSharesLiquidated(), "should be liquidated after first call");

        // Second call reverts — guarantees the creator payout (and oracle fee) happen exactly once
        vm.expectRevert(IDynamicParimutuelMarketErrors.MarketCreationSharesAlreadyLiquidated.selector);
        gateway.liquidateMarketCreationShares(marketProxy);
    }

    /// @dev A trader can always recover funds via liquidate even when the market creator is
    ///      blocked by the token (e.g. blacklist). Creator-share liquidation is decoupled, so the trader's
    ///      exit never routes a transfer to the creator; the creator's own claim stays blocked (isolated to
    ///      them). Red without the fix — the old liquidate() auto-called the creator payout.
    function test_Liquidate_TraderRecovers_WhenCreatorBlacklisted() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket(); // OPEN, creator == CREATOR

        // USER buys outcome-0 shares so there is a pool and trader shares to liquidate.
        _buyWithApproval(USER, IDynamicParimutuelGateway(address(gateway)), marketProxy, 0, 1e18, type(uint256).max);

        // Warp past the settlement deadline → EXPIRED.
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.EXPIRED),
            "market should be EXPIRED"
        );

        // Simulate the market creator being blacklisted: any token transfer to them reverts.
        address creator = marketProxy.marketCreator();
        vm.mockCallRevert(address(token), abi.encodeWithSelector(token.transfer.selector, creator), "BLOCKED");

        // The trader can still liquidate and recover funds — exit is decoupled from the creator payout.
        uint256[] memory outcomeIndices = new uint256[](1);
        outcomeIndices[0] = 0;
        uint256 balBefore = token.balanceOf(USER);

        _useNewSender(USER);
        gateway.liquidate(marketProxy, outcomeIndices);

        assertGt(token.balanceOf(USER), balBefore, "trader should recover funds despite blacklisted creator");
        assertFalse(
            marketProxy.marketCreationSharesLiquidated(), "creator shares must not be auto-liquidated by trader exit"
        );

        // The creator's own claim remains blocked — isolated to them; no other party is affected.
        vm.expectRevert();
        gateway.liquidateMarketCreationShares(marketProxy);
    }

    function test_SetOracleRelayer_Reverts_ZeroAddress() external {
        _setUp(6, 0);

        vm.expectRevert(IDynamicParimutuelGatewayErrors.ZeroOracleRelayerAddress.selector);
        gateway.setOracleRelayer(address(0));
    }

    function test_SetOracleRelayer_Reverts_NotOwner(address caller) external {
        _setUp(6, 0);

        vm.assume(caller != GENSYN);
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        gateway.setOracleRelayer(makeAddr("relayer"));
    }

    function test_SetOracleRelayer_Success() external {
        // Use the no-relayer deploy so the relayer starts unset (previous == address(0)).
        _deployStack(6);

        address relayer = makeAddr("relayer");

        vm.expectEmit(true, true, false, true, address(gateway));
        emit IDynamicParimutuelGateway.OracleRelayerSet(address(0), relayer);

        gateway.setOracleRelayer(relayer);

        assertEq(gateway.oracleRelayer(), relayer, "oracle relayer should be updated");
    }

    function test_SetOracleRelayer_UpdatesFromExistingValue() external {
        _setUp(6, 0);

        address first = makeAddr("first");
        address second = makeAddr("second");

        gateway.setOracleRelayer(first);

        vm.expectEmit(true, true, false, false, address(gateway));
        emit IDynamicParimutuelGateway.OracleRelayerSet(first, second);

        gateway.setOracleRelayer(second);

        assertEq(gateway.oracleRelayer(), second, "oracle relayer should be updated to second");
    }

    function test_Ownable2Step_TransferOwnership() external {
        _setUp(6, 0);

        address newOwner = makeAddr("NEW_OWNER");

        gateway.transferOwnership(newOwner);
        assertEq(gateway.pendingOwner(), newOwner, "pendingOwner should be set");
        assertEq(gateway.owner(), GENSYN, "owner should not change until accepted");

        _useNewSender(newOwner);
        gateway.acceptOwnership();
        assertEq(gateway.owner(), newOwner, "owner should be updated after acceptance");
        assertEq(gateway.pendingOwner(), address(0), "pendingOwner should be cleared");
    }

    // ======== MARKET - isValidOutcomeIdx ========

    function test_IsValidOutcomeIdx(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);

        deal(address(token), CREATOR, args.initialDeposit);
        token.approve(address(delphiFactory), args.initialDeposit);

        IDynamicParimutuelMarket marketProxy = IDynamicParimutuelMarket(
            delphiFactory.deployNewMarketProxy({
                initialDeposit_: args.initialDeposit,
                newMarketMetadata_: args.newMarketMetadata,
                newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
            })
        );

        uint256 outcomeCount = args.newMarketConfig.outcomeCount;
        for (uint256 i = 0; i < outcomeCount; i++) {
            assertTrue(marketProxy.isValidOutcomeIdx(i), "in-range outcome should be valid");
        }
        assertFalse(marketProxy.isValidOutcomeIdx(outcomeCount), "outcomeCount itself should be invalid");
        assertFalse(marketProxy.isValidOutcomeIdx(type(uint256).max), "max uint256 should be invalid");
    }

    // ======== MARKET SETTLED EVENT ========

    function test_SettleMarket_EmitsMarketSettledEvent(uint8 winningOutcomeIdx) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();
        _lockSettlement(gateway, mockOracleRelayer, address(marketProxy));

        winningOutcomeIdx = uint8(bound(winningOutcomeIdx, 0, implementation.MIN_OUTCOME_COUNT() - 1));

        vm.expectEmit(false, false, false, false, address(marketProxy));
        emit IDynamicParimutuelMarket.MarketSettled(winningOutcomeIdx, 0, 0, 0);

        _useNewSender(address(mockOracleRelayer));
        gateway.settleMarket(address(marketProxy), winningOutcomeIdx, address(0));
    }

    // ======== KEEPER FEE ========

    function testFuzz_Factory_FeesForwardedToMarket(uint256 keeperFee, uint256 oracleFee, uint256 marketCreationFee)
        external
    {
        _setUp(6, 0);
        uint256 maxFee = delphiFactory.MAX_MARKET_CREATION_FEE();

        marketCreationFee = bound(marketCreationFee, 0, maxFee);
        keeperFee = bound(keeperFee, 0, marketCreationFee);
        oracleFee = bound(oracleFee, 0, marketCreationFee - keeperFee);

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });
        DelphiFactory _factory = new DelphiFactory({
            implementation: address(_impl), marketCreationFee: marketCreationFee, marketCreationFeeRecipient: GENSYN
        });
        _gateway.initialize(IDelphiFactory(address(_factory)));

        // Wire a relayer so market creation passes the oracle-relayer guard.
        MockOracleRelayer _oracle = new MockOracleRelayer(_gateway);
        _gateway.setOracleRelayer(address(_oracle));

        _useNewSender(CREATOR);
        uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();

        deal(address(token), CREATOR, initialDeposit + marketCreationFee);
        token.approve(address(_factory), initialDeposit + marketCreationFee);

        address marketProxy = _factory.deployNewMarketProxy({
            initialDeposit_: initialDeposit,
            newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
            newMarketInitializationCalldata_: abi.encode(
                IDynamicParimutuelMarketTypes.MarketConfig({
                    outcomeCount: _impl.MIN_OUTCOME_COUNT(),
                    k: _impl.MIN_K(),
                    tradingFee: _impl.MIN_TRADING_FEE(),
                    tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
                    settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_SETTLEMENT_WINDOW()
                })
            )
        });

        assertEq(
            token.balanceOf(marketProxy),
            initialDeposit + keeperFee + oracleFee,
            "market proxy should hold initialDeposit + keeperFee + oracleFee"
        );
        assertEq(
            token.balanceOf(GENSYN),
            marketCreationFee - keeperFee - oracleFee,
            "recipient should receive remainder of market creation fee"
        );
    }

    function testFuzz_ResolveMarket_TransfersKeeperFee(uint256 keeperFee) external {
        _setUp(6, 0);
        keeperFee = bound(keeperFee, 0, delphiFactory.MAX_MARKET_CREATION_FEE());

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: keeperFee,
            oracleFee: 0
        });
        DelphiFactory _factory = new DelphiFactory({
            implementation: address(_impl), marketCreationFee: keeperFee, marketCreationFeeRecipient: GENSYN
        });
        _gateway.initialize(IDelphiFactory(address(_factory)));
        MockOracleRelayer _oracle = new MockOracleRelayer(_gateway);
        _gateway.setOracleRelayer(address(_oracle));

        _useNewSender(CREATOR);
        uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();

        deal(address(token), CREATOR, initialDeposit + keeperFee);
        token.approve(address(_factory), initialDeposit + keeperFee);

        IDynamicParimutuelMarket marketProxy = IDynamicParimutuelMarket(
            _factory.deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
                newMarketInitializationCalldata_: abi.encode(
                    IDynamicParimutuelMarketTypes.MarketConfig({
                        outcomeCount: _impl.MIN_OUTCOME_COUNT(),
                        k: _impl.MIN_K(),
                        tradingFee: _impl.MIN_TRADING_FEE(),
                        tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
                        settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_SETTLEMENT_WINDOW()
                    })
                )
            })
        );

        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);
        _oracle.setOutcome(address(marketProxy), 0);

        address keeper = makeAddr("keeper");
        uint256 keeperBalanceBefore = token.balanceOf(keeper);
        uint256 marketBalanceBefore = token.balanceOf(address(marketProxy));

        // Silence the oracle callback so only the keeper-fee transfer happens in this call,
        // allowing us to assert the market balance decrease in isolation.
        vm.mockCall(
            address(_oracle), abi.encodeWithSelector(IOracle.resolveMarket.selector, address(marketProxy)), abi.encode()
        );

        _useNewSender(keeper);
        _gateway.resolveMarket(address(marketProxy));

        assertEq(token.balanceOf(keeper) - keeperBalanceBefore, keeperFee, "keeper should receive exactly KEEPER_FEE");
        assertEq(
            marketBalanceBefore - token.balanceOf(address(marketProxy)),
            keeperFee,
            "market balance should decrease by KEEPER_FEE"
        );
    }

    /// @dev Deploys a standalone gateway/impl/factory/oracle with the given keeperFee (oracleFee 0),
    ///      and a market in OPEN state. Assumes _setUp has been called. Used by the keeper-fee-on-expiry tests.
    function _deployKeeperFeeMarket(uint256 keeperFee)
        private
        returns (DynamicParimutuelGateway g, IDynamicParimutuelMarket m, MockOracleRelayer o)
    {
        _useNewSender(GENSYN);
        g = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(g),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: keeperFee,
            oracleFee: 0
        });
        DelphiFactory f = new DelphiFactory({
            implementation: address(impl), marketCreationFee: keeperFee, marketCreationFeeRecipient: GENSYN
        });
        g.initialize(IDelphiFactory(address(f)));
        o = new MockOracleRelayer(g);
        g.setOracleRelayer(address(o));

        _useNewSender(CREATOR);
        uint256 initialDeposit = impl.MIN_INITIAL_DEPOSIT();
        deal(address(token), CREATOR, initialDeposit + keeperFee);
        token.approve(address(f), initialDeposit + keeperFee);
        m = IDynamicParimutuelMarket(
            f.deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
                newMarketInitializationCalldata_: abi.encode(
                    IDynamicParimutuelMarketTypes.MarketConfig({
                        outcomeCount: impl.MIN_OUTCOME_COUNT(),
                        k: impl.MIN_K(),
                        tradingFee: impl.MIN_TRADING_FEE(),
                        tradingDeadline: block.timestamp + impl.MIN_TRADING_WINDOW(),
                        settlementDeadline: block.timestamp + impl.MIN_TRADING_WINDOW() + impl.MIN_SETTLEMENT_WINDOW()
                    })
                )
            })
        );
    }

    function testFuzz_Liquidate_ReturnsKeeperFeeToCreator_WhenNeverResolved(uint256 keeperFee) external {
        _setUp(6, 0);
        keeperFee = bound(keeperFee, 1, delphiFactory.MAX_MARKET_CREATION_FEE());

        (DynamicParimutuelGateway g, IDynamicParimutuelMarket m,) = _deployKeeperFeeMarket(keeperFee);

        // Expire the market WITHOUT ever calling resolveMarket → keeper fee never disbursed
        vm.warp(m.getMarket().config.settlementDeadline + 1);
        assertEq(
            uint8(m.marketStatus()), uint8(IDynamicParimutuelMarketTypes.MarketStatus.EXPIRED), "should be EXPIRED"
        );
        assertFalse(m.keeperFeePaid(), "keeper fee should not be paid (never resolved)");

        uint256 expectedCreatorTotal = m.marketCreatorTotalSharesLiquidationValue() + m.getMarket().refund + keeperFee;
        uint256 creatorBefore = token.balanceOf(CREATOR);

        g.liquidateMarketCreationShares(m);

        assertEq(
            token.balanceOf(CREATOR) - creatorBefore,
            expectedCreatorTotal,
            "creator should receive liquidation value + refund + stranded keeper fee"
        );
    }

    function testFuzz_Liquidate_DoesNotReturnKeeperFee_WhenResolvedButOracleSilent(uint256 keeperFee) external {
        _setUp(6, 0);
        keeperFee = bound(keeperFee, 1, delphiFactory.MAX_MARKET_CREATION_FEE());

        (DynamicParimutuelGateway g, IDynamicParimutuelMarket m, MockOracleRelayer o) =
            _deployKeeperFeeMarket(keeperFee);

        vm.warp(m.getMarket().config.tradingDeadline + 1); // AWAITING_SETTLEMENT

        // Keeper resolves; silence the oracle so it never calls back (market stays AWAITING_SETTLEMENT)
        vm.mockCall(address(o), abi.encodeWithSelector(IOracle.resolveMarket.selector, address(m)), abi.encode());
        address keeper = makeAddr("keeper");
        uint256 keeperBefore = token.balanceOf(keeper);
        _useNewSender(keeper);
        g.resolveMarket(address(m));
        assertEq(token.balanceOf(keeper) - keeperBefore, keeperFee, "keeper got the fee at resolve");
        assertTrue(m.keeperFeePaid(), "keeper fee marked paid");

        // Oracle never responds → market expires
        vm.warp(m.getMarket().config.settlementDeadline + 1);

        uint256 expectedCreatorTotal = m.marketCreatorTotalSharesLiquidationValue() + m.getMarket().refund; // NO keeper fee
        uint256 creatorBefore = token.balanceOf(CREATOR);

        g.liquidateMarketCreationShares(m);

        assertEq(
            token.balanceOf(CREATOR) - creatorBefore,
            expectedCreatorTotal,
            "creator should NOT receive the keeper fee (already paid to keeper at resolve)"
        );
    }

    function testFuzz_Liquidate_DoesNotReturnKeeperFee_WhenFailed(uint256 keeperFee) external {
        _setUp(6, 0);
        keeperFee = bound(keeperFee, 1, delphiFactory.MAX_MARKET_CREATION_FEE());

        (DynamicParimutuelGateway g, IDynamicParimutuelMarket m, MockOracleRelayer o) =
            _deployKeeperFeeMarket(keeperFee);

        vm.warp(m.getMarket().config.tradingDeadline + 1); // AWAITING_SETTLEMENT

        // Keeper resolves (gets fee); silence the oracle callback, then fail the market as the relayer
        vm.mockCall(address(o), abi.encodeWithSelector(IOracle.resolveMarket.selector, address(m)), abi.encode());
        address keeper = makeAddr("keeper");
        uint256 keeperBefore = token.balanceOf(keeper);
        _useNewSender(keeper);
        g.resolveMarket(address(m));
        assertEq(token.balanceOf(keeper) - keeperBefore, keeperFee, "keeper got the fee at resolve");

        _useNewSender(address(o));
        g.failMarket(address(m));
        assertEq(uint8(m.marketStatus()), uint8(IDynamicParimutuelMarketTypes.MarketStatus.FAILED), "should be FAILED");

        uint256 expectedCreatorTotal = m.marketCreatorTotalSharesLiquidationValue() + m.getMarket().refund; // NO keeper fee
        uint256 creatorBefore = token.balanceOf(CREATOR);

        g.liquidateMarketCreationShares(m);

        assertEq(
            token.balanceOf(CREATOR) - creatorBefore,
            expectedCreatorTotal,
            "creator should NOT receive the keeper fee on FAILED (paid to keeper at resolve)"
        );
    }

    function testFuzz_Liquidate_ReturnsOracleFeeToCreator(uint256 oracleFee) external {
        _setUp(6, 0);
        oracleFee = bound(oracleFee, 1, delphiFactory.MAX_MARKET_CREATION_FEE());

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: 0,
            oracleFee: oracleFee
        });
        DelphiFactory _factory = new DelphiFactory({
            implementation: address(_impl), marketCreationFee: oracleFee, marketCreationFeeRecipient: GENSYN
        });
        _gateway.initialize(IDelphiFactory(address(_factory)));
        MockOracleRelayer _oracle = new MockOracleRelayer(_gateway);
        _gateway.setOracleRelayer(address(_oracle));

        _useNewSender(CREATOR);
        uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();
        deal(address(token), CREATOR, initialDeposit + oracleFee);
        token.approve(address(_factory), initialDeposit + oracleFee);

        IDynamicParimutuelMarket marketProxy = IDynamicParimutuelMarket(
            _factory.deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
                newMarketInitializationCalldata_: abi.encode(
                    IDynamicParimutuelMarketTypes.MarketConfig({
                        outcomeCount: _impl.MIN_OUTCOME_COUNT(),
                        k: _impl.MIN_K(),
                        tradingFee: _impl.MIN_TRADING_FEE(),
                        tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
                        settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_SETTLEMENT_WINDOW()
                    })
                )
            })
        );

        // Advance past settlement deadline → EXPIRED
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        uint256 creatorBalanceBefore = token.balanceOf(CREATOR);
        uint256 recipientBalanceBefore = token.balanceOf(GENSYN);

        _gateway.liquidateMarketCreationShares(marketProxy);

        // Creator gets back everything: oracle fee + liquidation value + refund (no trading fees since no trades)
        uint256 creatorReceived = token.balanceOf(CREATOR) - creatorBalanceBefore;
        assertTrue(creatorReceived >= oracleFee, "creator should receive at least ORACLE_FEE");
        // Recipient gets nothing (no trading fees accumulated)
        assertEq(
            token.balanceOf(GENSYN),
            recipientBalanceBefore,
            "trading fees recipient should receive nothing when no trades occurred"
        );
    }

    function testFuzz_LiquidateMarketCreationShares_CreatorGetsBack(uint256 oracleFee) external {
        _setUp(6, 0);
        // Keep oracleFee small enough that the market has sufficient liquidity for a test buy
        oracleFee = bound(oracleFee, 1, 1_000_000); // max 1 USDC
        uint256 tradingFeesRecipientPct = 0.1e18; // 10%

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: tradingFeesRecipientPct,
            keeperFee: 0,
            oracleFee: oracleFee
        });
        DelphiFactory _factory = new DelphiFactory({
            implementation: address(_impl), marketCreationFee: oracleFee, marketCreationFeeRecipient: GENSYN
        });
        _gateway.initialize(IDelphiFactory(address(_factory)));
        MockOracleRelayer _oracle = new MockOracleRelayer(_gateway);
        _gateway.setOracleRelayer(address(_oracle));

        _useNewSender(CREATOR);
        uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();
        deal(address(token), CREATOR, initialDeposit + oracleFee);
        token.approve(address(_factory), initialDeposit + oracleFee);

        IDynamicParimutuelMarket marketProxy = IDynamicParimutuelMarket(
            _factory.deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
                newMarketInitializationCalldata_: abi.encode(
                    IDynamicParimutuelMarketTypes.MarketConfig({
                        outcomeCount: _impl.MIN_OUTCOME_COUNT(),
                        k: _impl.MIN_K(),
                        tradingFee: _impl.MIN_TRADING_FEE(),
                        tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
                        settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_SETTLEMENT_WINDOW()
                    })
                )
            })
        );

        // Advance past settlement deadline → EXPIRED (no trades — pure position + oracle fee refund)
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);

        uint256 expectedCreatorTotal =
            marketProxy.marketCreatorTotalSharesLiquidationValue() + marketProxy.getMarket().refund + oracleFee;

        uint256 creatorBalanceBefore = token.balanceOf(CREATOR);
        uint256 recipientBalanceBefore = token.balanceOf(GENSYN);

        _gateway.liquidateMarketCreationShares(marketProxy);

        assertEq(
            token.balanceOf(CREATOR) - creatorBalanceBefore,
            expectedCreatorTotal,
            "creator should receive liquidation value + refund + oracle fee"
        );
        // No trades occurred so recipient gets nothing
        assertEq(
            token.balanceOf(GENSYN), recipientBalanceBefore, "recipient should receive nothing when no trades occurred"
        );
    }

    function testFuzz_LiquidateAfterFail_OracleFeeTransferredOnce(uint256 oracleFee) external {
        _setUp(6, 0);
        oracleFee = bound(oracleFee, 1, delphiFactory.MAX_MARKET_CREATION_FEE());

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: 0,
            oracleFee: oracleFee
        });
        DelphiFactory _factory = new DelphiFactory({
            implementation: address(_impl), marketCreationFee: oracleFee, marketCreationFeeRecipient: GENSYN
        });
        _gateway.initialize(IDelphiFactory(address(_factory)));
        MockOracleRelayer _oracle = new MockOracleRelayer(_gateway);
        _gateway.setOracleRelayer(address(_oracle));

        _useNewSender(CREATOR);
        uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();
        deal(address(token), CREATOR, initialDeposit + oracleFee);
        token.approve(address(_factory), initialDeposit + oracleFee);

        IDynamicParimutuelMarket marketProxy = IDynamicParimutuelMarket(
            _factory.deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")}),
                newMarketInitializationCalldata_: abi.encode(
                    IDynamicParimutuelMarketTypes.MarketConfig({
                        outcomeCount: _impl.MIN_OUTCOME_COUNT(),
                        k: _impl.MIN_K(),
                        tradingFee: _impl.MIN_TRADING_FEE(),
                        tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
                        settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_SETTLEMENT_WINDOW()
                    })
                )
            })
        );

        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // failMarket does NOT transfer oracle fee (would cause double payment)
        _lockSettlement(_gateway, _oracle, address(marketProxy));

        uint256 creatorBalanceAfterFail = token.balanceOf(CREATOR);
        _useNewSender(address(_oracle));
        _gateway.failMarket(address(marketProxy));
        assertEq(token.balanceOf(CREATOR), creatorBalanceAfterFail, "failMarket should not transfer oracle fee");

        // liquidateMarketCreationShares transfers oracle fee exactly once (along with rest of creator's payout)
        uint256 liquidationValue = marketProxy.marketCreatorTotalSharesLiquidationValue();
        uint256 refund = marketProxy.getMarket().refund;
        _gateway.liquidateMarketCreationShares(marketProxy);
        assertEq(
            token.balanceOf(CREATOR) - creatorBalanceAfterFail,
            liquidationValue + refund + oracleFee,
            "oracle fee should be transferred exactly once via liquidateMarketCreationShares"
        );
    }

    function testFuzz_Factory_Constructor_Reverts_FeesExceedCreationFee(
        uint256 keeperFee,
        uint256 oracleFee,
        uint256 marketCreationFee
    ) external {
        _setUp(6, 0);
        uint256 maxFee = delphiFactory.MAX_MARKET_CREATION_FEE();

        marketCreationFee = bound(marketCreationFee, 0, maxFee);
        keeperFee = bound(keeperFee, 0, maxFee);
        oracleFee = bound(oracleFee, 0, maxFee);
        vm.assume(keeperFee + oracleFee > marketCreationFee);

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IDelphiFactoryErrors.SettlementFeesExceedMarketCreationFee.selector,
                keeperFee + oracleFee,
                marketCreationFee
            )
        );
        new DelphiFactory({
            implementation: address(_impl), marketCreationFee: marketCreationFee, marketCreationFeeRecipient: GENSYN
        });
    }

    function testFuzz_Factory_Constructor_FeesEqualCreationFee(uint256 keeperFee, uint256 oracleFee) external {
        _setUp(6, 0);
        uint256 maxFee = delphiFactory.MAX_MARKET_CREATION_FEE();

        keeperFee = bound(keeperFee, 0, maxFee);
        oracleFee = bound(oracleFee, 0, maxFee - keeperFee);
        uint256 marketCreationFee = keeperFee + oracleFee;

        _useNewSender(GENSYN);
        DynamicParimutuelGateway _gateway = new DynamicParimutuelGateway(token, GENSYN);
        DynamicParimutuelMarket _impl = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN,
            gateway: address(_gateway),
            tradingFeesRecipientPct: 0.1e18,
            keeperFee: keeperFee,
            oracleFee: oracleFee
        });
        DelphiFactory _factory = new DelphiFactory({
            implementation: address(_impl), marketCreationFee: marketCreationFee, marketCreationFeeRecipient: GENSYN
        });
        assertEq(_factory.SETTLEMENT_FEES(), marketCreationFee);
    }

    function test_ResolveMarket_Reverts_OnlyGateway(address caller) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.assume(caller != address(gateway));
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(IDynamicParimutuelMarketErrors.CallerNotGateway.selector, caller));
        marketProxy.transferKeeperFee(caller);
    }

    function test_ResolveMarket_Reverts_WrongMarketStatus() external {
        // Market is in OPEN status (no warp past trading deadline)
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        _useNewSender(GENSYN);
        mockOracleRelayer = new MockOracleRelayer(gateway);
        gateway.setOracleRelayer(address(mockOracleRelayer));

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.WrongMarketStatus.selector,
                IDynamicParimutuelMarketTypes.MarketStatus.OPEN,
                IDynamicParimutuelMarketTypes.MarketStatus.AWAITING_SETTLEMENT
            )
        );
        gateway.resolveMarket(address(marketProxy));
    }

    // ========== PERMIT ==========

    function test_BuyWithPermit_UsedPermit(uint256 buyerPk, uint256 outcomeIdx, uint256 sharesOut) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        buyerPk = bound(buyerPk, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - 1);

        uint256 max = 10_000_000e18;
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);
        sharesOut = bound(sharesOut, 1e18, max);
        uint256 maxTokensIn = 2 * sharesOut / gateway.TOKEN_DECIMAL_SCALER();
        uint256 deadline = block.timestamp + 1;

        address buyer = vm.addr(buyerPk);
        deal(address(token), buyer, maxTokensIn);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(marketProxy, buyerPk, maxTokensIn, deadline);

        _useNewSender(buyer);
        IERC20Permit(address(token))
            .permit({
            owner: buyer, spender: address(marketProxy), value: maxTokensIn, deadline: deadline, v: v, r: r, s: s
        });

        // The nonce is now consumed, so the wrapper's inner permit reverts and the catch recovers using
        // the allowance set above. The buy must still complete — assert the buyer actually got the shares.
        gateway.buyExactOutWithPermit(marketProxy, outcomeIdx, sharesOut, maxTokensIn, deadline, v, r, s);

        assertEq(marketProxy.balanceOf(buyer, outcomeIdx), sharesOut, "buyer should receive sharesOut via recovery");
    }

    function test_BuyWithPermit_AllowanceTooLow_Reverts(uint256 buyerPk, uint256 outcomeIdx, uint256 sharesOut)
        external
    {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        buyerPk = bound(buyerPk, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - 1);

        uint256 max = 10_000_000e18;
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);
        sharesOut = bound(sharesOut, 1e18, max);
        uint256 maxTokensIn = 2 * sharesOut / gateway.TOKEN_DECIMAL_SCALER();
        uint256 deadline = block.timestamp + 1;

        address buyer = vm.addr(buyerPk);
        deal(address(token), buyer, maxTokensIn);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(marketProxy, buyerPk, maxTokensIn, deadline);
        s = bytes32(uint256(s) + 1); // invalidate signature

        _useNewSender(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.AllowanceTooLow.selector,
                0, // allowance
                maxTokensIn // maxTokensIn
            )
        );
        gateway.buyExactOutWithPermit(marketProxy, outcomeIdx, sharesOut, maxTokensIn, deadline, v, r, s);
    }

    /// @dev Happy path: a fresh, valid permit succeeds (the wrapper's `try` branch), the catch is never
    ///      entered, and the buy completes. Asserts the buyer received the shares and paid the tokens.
    function test_BuyWithPermit_Success(uint256 buyerPk, uint256 outcomeIdx, uint256 sharesOut) external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        buyerPk = bound(buyerPk, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - 1);

        uint256 max = 10_000_000e18;
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);
        sharesOut = bound(sharesOut, 1e18, max);
        uint256 maxTokensIn = 2 * sharesOut / gateway.TOKEN_DECIMAL_SCALER();
        uint256 deadline = block.timestamp + 1;

        address buyer = vm.addr(buyerPk);
        deal(address(token), buyer, maxTokensIn);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(marketProxy, buyerPk, maxTokensIn, deadline);

        _useNewSender(buyer);
        uint256 tokensIn =
            gateway.buyExactOutWithPermit(marketProxy, outcomeIdx, sharesOut, maxTokensIn, deadline, v, r, s);

        assertEq(marketProxy.balanceOf(buyer, outcomeIdx), sharesOut, "buyer should receive sharesOut");
        assertGt(tokensIn, 0, "tokensIn should be > 0");
        assertLe(tokensIn, maxTokensIn, "tokensIn should not exceed maxTokensIn");
        assertEq(token.balanceOf(buyer), maxTokensIn - tokensIn, "buyer token balance should drop by tokensIn");
    }

    /// @dev Catch path with a non-zero but insufficient allowance: the revert must report the actual
    ///      (partial) allowance, not 0 — distinct from the allowance==0 case.
    function test_BuyWithPermit_PartialAllowance_Reverts(uint256 buyerPk, uint256 outcomeIdx, uint256 sharesOut)
        external
    {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        buyerPk = bound(buyerPk, 1, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - 1);

        uint256 max = 10_000_000e18;
        outcomeIdx = bound(outcomeIdx, 0, marketProxy.getMarket().config.outcomeCount - 1);
        sharesOut = bound(sharesOut, 1e18, max);
        uint256 maxTokensIn = 2 * sharesOut / gateway.TOKEN_DECIMAL_SCALER();
        uint256 deadline = block.timestamp + 1;

        address buyer = vm.addr(buyerPk);
        deal(address(token), buyer, maxTokensIn);

        // Pre-existing allowance to the market proxy: non-zero but below maxTokensIn.
        uint256 partialAllowance = maxTokensIn / 2;
        _useNewSender(buyer);
        token.approve(address(marketProxy), partialAllowance);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(marketProxy, buyerPk, maxTokensIn, deadline);
        s = bytes32(uint256(s) + 1); // invalidate signature → permit reverts → catch

        // Catch reads the (insufficient) market-proxy allowance and reverts with the actual value.
        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelGatewayErrors.AllowanceTooLow.selector, partialAllowance, maxTokensIn
            )
        );
        gateway.buyExactOutWithPermit(marketProxy, outcomeIdx, sharesOut, maxTokensIn, deadline, v, r, s);
    }

    // ========== INTERNAL HELPERS ==========

    function _scaledAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return amount / (10 ** (18 - decimals));
    }

    /// @dev Lock a market for settlement via the real `gateway.resolveMarket`, with the mock relayer in
    ///      lock-only mode so the market is locked but NOT settled (mirrors production state before the
    ///      oracle responds). Lets settleMarket/failMarket be tested in isolation against the
    ///      `SettlementNotLocked` guard. Requires the market to be AWAITING_SETTLEMENT.
    function _lockSettlement(DynamicParimutuelGateway gw, MockOracleRelayer relayer_, address marketProxy) internal {
        relayer_.setLockOnly(true);
        _useNewSender(makeAddr("keeper"));
        gw.resolveMarket(marketProxy);
        relayer_.setLockOnly(false);
    }
}
