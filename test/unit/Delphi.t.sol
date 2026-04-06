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
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

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
import {
    IDynamicParimutuelGatewayErrors
} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGatewayErrors.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

    function _setUp(
        uint8 decimals,
        uint256 /*marketCreationFee*/
    )
        internal
        returns (uint8)
    {
        decimals = _boundUint8(decimals, 6, 18);
        // uint256 maxMarketCreationFee = 1_000 * (10 ** decimals); // 1K tokens
        // marketCreationFee = bound(marketCreationFee, 0, maxMarketCreationFee);

        _useNewSender(GENSYN);
        token = new MockToken({_decimals: decimals, admin: GENSYN, initialAmount: 0});

        // Deploy All
        DelphiAddresses memory deployment = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: GENSYN,
                marketCreationFeeRecipient: GENSYN,
                marketCreationFee: 0,
                tradingFeesRecipientPct: 0.1e18,
                token: token
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
        IERC20Metadata _token = new MockToken({_decimals: decimals, admin: GENSYN, initialAmount: 0});
        DynamicParimutuelGateway _dynamicParimutuelGateway = new DynamicParimutuelGateway(_token);

        // Deploy DynamicParimutuel Implementation
        DynamicParimutuelMarket _dynamicParimutuelImplementation = new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN, gateway: address(_dynamicParimutuelGateway), tradingFeesRecipientPct: 0.1e18
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

        token = new MockToken({_decimals: _boundUint8(decimals, 6, 18), admin: GENSYN, initialAmount: 0});

        DynamicParimutuelGateway _dynamicParimutuelGateway = new DynamicParimutuelGateway(token);

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
            initialLiquidity_: args.initialLiquidity,
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
                IERC20Errors.ERC20InsufficientAllowance.selector, delphiFactory, 0, args.initialLiquidity
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.OutcomeCountTooLow.selector,
                args.newMarketConfig.outcomeCount,
                implementation.MIN_OUTCOME_COUNT()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.OutcomeCountTooHigh.selector,
                args.newMarketConfig.outcomeCount,
                implementation.MAX_OUTCOME_COUNT()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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
        args.newMarketConfig.b = bound(args.newMarketConfig.b, 0, implementation.MIN_B() - 1);

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.KTooLow.selector, args.newMarketConfig.b, implementation.MIN_B()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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
        args.newMarketConfig.b = bound(args.newMarketConfig.b, implementation.MAX_B() + 1, type(uint256).max);

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.KTooHigh.selector, args.newMarketConfig.b, implementation.MAX_B()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingFeeTooLow.selector,
                args.newMarketConfig.tradingFee,
                implementation.MIN_TRADING_FEE()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingFeeTooHigh.selector,
                args.newMarketConfig.tradingFee,
                implementation.MAX_TRADING_FEE()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingDeadlineNotInFuture.selector,
                args.newMarketConfig.tradingDeadline,
                block.timestamp
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingWindowTooShort.selector,
                args.newMarketConfig.tradingDeadline - block.timestamp,
                implementation.MIN_TRADING_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingWindowTooLong.selector,
                args.newMarketConfig.tradingDeadline - block.timestamp,
                implementation.MAX_TRADING_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.SettlementDeadlineBeforeTradingDeadline.selector,
                args.newMarketConfig.settlementDeadline,
                args.newMarketConfig.tradingDeadline
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.SettlementWindowTooShort.selector,
                args.newMarketConfig.settlementDeadline - args.newMarketConfig.tradingDeadline,
                implementation.MIN_SETTLEMENT_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.SettlementWindowTooLong.selector,
                args.newMarketConfig.settlementDeadline - args.newMarketConfig.tradingDeadline,
                implementation.MAX_SETTLEMENT_WINDOW()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(IDynamicParimutuelMarketErrors.EmptyUri.selector);
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(IDynamicParimutuelMarketErrors.EmptyUriContentHash.selector);
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_InitialLiquidityTooLow(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.initialLiquidity = bound(args.initialLiquidity, 0, implementation.MIN_INITIAL_LIQUIDITY() - 1);

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.InitialLiquidityTooLow.selector,
                args.initialLiquidity,
                implementation.MIN_INITIAL_LIQUIDITY()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
            newMarketMetadata_: args.newMarketMetadata,
            newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
        });
    }

    function test_CreateMarket_Reverts_InitialLiquidityTooHigh(
        uint8 decimals,
        uint256 marketCreationFee,
        IEndToEndHandler.DeployMarketArgs memory args
    ) external {
        decimals = _setUp(decimals, marketCreationFee);
        _useNewSender(CREATOR);

        args.marketCreator = CREATOR;
        args = _boundDeployMarketArgs(implementation, args);
        args.initialLiquidity =
            bound(args.initialLiquidity, implementation.MAX_INITIAL_LIQUIDITY() + 1, type(uint256).max);

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.InitialLiquidityTooHigh.selector,
                args.initialLiquidity,
                implementation.MAX_INITIAL_LIQUIDITY()
            )
        );
        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

        delphiFactory.deployNewMarketProxy({
            initialLiquidity_: args.initialLiquidity,
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

        deal(address(token), CREATOR, args.initialLiquidity);
        token.approve(address(delphiFactory), args.initialLiquidity);

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

        uint256 initialLiquidity = implementation.MIN_INITIAL_LIQUIDITY();
        uint256 minTradingWindow = implementation.MIN_TRADING_WINDOW();

        IDynamicParimutuelMarketTypes.MarketConfig memory config = IDynamicParimutuelMarketTypes.MarketConfig({
            outcomeCount: implementation.MIN_OUTCOME_COUNT(),
            b: implementation.MIN_B(),
            tradingFee: implementation.MIN_TRADING_FEE(),
            tradingDeadline: block.timestamp + minTradingWindow,
            settlementDeadline: block.timestamp + minTradingWindow + implementation.MIN_SETTLEMENT_WINDOW()
        });

        deal(address(token), CREATOR, initialLiquidity);
        token.approve(address(delphiFactory), initialLiquidity);

        marketProxy = IDynamicParimutuelMarket(
            delphiFactory.deployNewMarketProxy({
                initialLiquidity_: initialLiquidity,
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

        // With MIN_B and MIN_INITIAL_LIQUIDITY, buying MIN_SHARES_DELTA shares
        // produces tokensIn well below minTokensDelta (1e4 for 6 decimals)
        vm.expectPartialRevert(IDynamicParimutuelGatewayErrors.TokensInBelowMin.selector);
        gateway.quoteBuyExactOut(marketProxy, 0, minSharesDelta);
    }

    function test_Gateway_Reverts_TokensOutBelowMin() external {
        IDynamicParimutuelMarket marketProxy = _setUpMarket();

        uint256 minSharesDelta = gateway.MIN_SHARES_DELTA();

        // With MIN_B and MIN_INITIAL_LIQUIDITY, selling a small amount of shares
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

        DynamicParimutuelGateway newGateway = new DynamicParimutuelGateway(token);

        vm.expectRevert(
            abi.encodeWithSelector(
                IDynamicParimutuelMarketErrors.TradingFeesRecipientPctTooHigh.selector,
                tradingFeesRecipientPct,
                implementation.MAX_TRADING_FEES_RECIPIENT_PCT()
            )
        );
        new DynamicParimutuelMarket({
            tradingFeesRecipient: GENSYN, gateway: address(newGateway), tradingFeesRecipientPct: tradingFeesRecipientPct
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

    // ========== INTERNAL HELPERS ==========

    function _scaledAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return amount / (10 ** (18 - decimals));
    }
}
