// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TruebitOracleRelayer} from "src/oracle/TruebitOracleRelayer.sol";
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {IWatchTower} from "src/oracle/truebit/interfaces/IWatchTower.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TruebitOracleRelayerV2} from "test/support/mocks/TruebitOracleRelayerV2.sol";
import {TruebitOracleRelayerDeployer} from "script/utils/deployer/TruebitOracleRelayerDeployer.sol";
import {DelphiFactory} from "src/factory/DelphiFactory.sol";

// Interfaces
import {ILmsrGateway} from "src/lmsr/gateway/ILmsrGateway.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {IDelphiMarket} from "src/IDelphiMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {DOTypes} from "src/oracle/truebit/abstract/Types.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract TruebitOracleRelayer_Test is DelphiTestUtils, TruebitOracleRelayerDeployer {
    // Actors
    address immutable OWNER = makeAddr("OWNER");
    address immutable CREATOR = makeAddr("CREATOR");
    address immutable WATCH_TOWER = makeAddr("WATCH_TOWER");
    address immutable ORACLE_FEE_RECIPIENT = makeAddr("ORACLE_FEE_RECIPIENT");

    // Token config
    uint8 constant TOKEN_DECIMALS = 6;
    uint256 constant TRADING_FEES_PCT = 0.1e18;

    // Truebit task params
    string constant NAMESPACE = "gensyn";
    string constant TASKNAME = "workflow_entry";
    string constant METHOD = "POST";
    string constant PATH = "/webhook/settlement";
    uint256 constant EXECUTION_TIMEOUT = 100000;
    bool constant ASYNC = true;

    // MockWatchTower starts its ID counter at 1 — first resolveMarket call always gets this ID
    uint256 constant FIRST_EXECUTION_ID = 1;

    // Contracts
    IERC20Metadata token;
    DelphiFactory factory;
    LmsrGateway gateway;
    LmsrMarket implementation;
    TruebitOracleRelayer relayer;

    // Libraries
    using LmsrMath for uint256;

    function _setUp() private {
        _useNewSender(OWNER);

        token = new MockToken({
            name: "MockToken", symbol: "MOCK", _decimals: TOKEN_DECIMALS, admin: OWNER, initialAmount: 0
        });

        DelphiAddresses memory delphi = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: OWNER,
                marketCreationFeeRecipient: OWNER,
                marketCreationFee: 0,
                keeperFee: 0,
                oracleFee: 0,
                tradingFeesRecipientPct: TRADING_FEES_PCT,
                token: token,
                gatewayOwner: OWNER
            })
        );

        factory = delphi.factory;
        gateway = delphi.gateway;
        implementation = delphi.implementation;

        // Deploy TruebitOracleRelayer impl + proxy
        TruebitOracleRelayer impl =
            new TruebitOracleRelayer(WATCH_TOWER, ILmsrGateway(address(gateway)), EXECUTION_TIMEOUT, ASYNC);

        relayer = TruebitOracleRelayer(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        TruebitOracleRelayer.initialize,
                        (TruebitOracleRelayer.InitParams({owner: OWNER, oracleFeeRecipient: ORACLE_FEE_RECIPIENT}))
                    )
                )
            )
        );

        gateway.setOracleRelayer(address(relayer));
    }

    function _setUpMarketAwaitingSettlement() private returns (ILmsrMarket marketProxy) {
        _setUp();
        ILmsrMarket _marketProxy = _createMarket();
        _warpToSettlementWindow(_marketProxy);
        return _marketProxy;
    }

    /// @dev Creates an additional market on the already-deployed gateway and warps it into
    ///      AWAITING_SETTLEMENT. Call after _setUp()/_setUpMarketAwaitingSettlement() to get a second
    ///      in-flight market on the same gateway (MIN_SETTLEMENT_WINDOW >> MIN_TRADING_WINDOW, so the
    ///      earlier market is still AWAITING_SETTLEMENT after the second one is warped in).
    function _createMarket() private returns (ILmsrMarket marketProxy) {
        _useNewSender(CREATOR);

        // uint256 initialDeposit = implementation.MIN_INITIAL_DEPOSIT();
        uint256 minTradingWindow = implementation.MIN_TRADING_WINDOW();

        ILmsrMarketTypes.MarketConfig memory config = ILmsrMarketTypes.MarketConfig({
            outcomeCount: implementation.MIN_OUTCOME_COUNT(),
            b: implementation.MIN_B(),
            tradingFee: implementation.MIN_TRADING_FEE(),
            tradingDeadline: block.timestamp + minTradingWindow,
            earliestResolveTime: block.timestamp + minTradingWindow + implementation.MIN_RESOLVE_DELAY(),
            settlementDeadline: block.timestamp + minTradingWindow + implementation.MIN_RESOLVE_DELAY()
                + implementation.MIN_SETTLEMENT_WINDOW()
        });

        uint256 maxLoss = config.b.maxLoss(config.outcomeCount, implementation.TOKEN_DECIMAL_SCALER());
        uint256 marketCreationFee = gateway.delphiFactory().MARKET_CREATION_FEE();
        uint256 initialDeposit = maxLoss + marketCreationFee;

        deal(address(token), CREATOR, initialDeposit);
        token.approve(address(gateway.delphiFactory()), initialDeposit);

        marketProxy = ILmsrMarket(
            gateway.delphiFactory()
                .deployNewMarketProxy({
                    initialDeposit_: initialDeposit,
                    newMarketConfig_: config,
                    newMarketMetadata: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")})
                })
        );
    }

    function _warpToSettlementWindow(ILmsrMarket marketProxy) internal {
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);
    }

    // ========== SET ORACLE FEE RECIPIENT ==========

    function test_SetOracleFeeRecipient_Reverts_ZeroAddress() external {
        _setUp();

        _useNewSender(OWNER);
        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.OracleFeeRecipientIsZeroAddress.selector));
        relayer.setOracleFeeRecipient(address(0));
    }

    function test_SetOracleFeeRecipient_Reverts_NotOwner(address caller) external {
        _setUp();

        vm.assume(caller != OWNER);
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        relayer.setOracleFeeRecipient(makeAddr("newRecipient"));
    }

    function test_SetOracleFeeRecipient_Success(address newRecipient) external {
        _setUp();

        vm.assume(newRecipient != address(0));

        vm.expectEmit(true, true, false, false, address(relayer));
        emit TruebitOracleRelayer.OracleFeeRecipientSet(ORACLE_FEE_RECIPIENT, newRecipient);

        _useNewSender(OWNER);
        relayer.setOracleFeeRecipient(newRecipient);

        assertEq(relayer.oracleFeeRecipient(), newRecipient, "oracleFeeRecipient should be updated");
    }

    function test_Initialize_Reverts_ZeroOracleFeeRecipient() external {
        _useNewSender(OWNER);

        TruebitOracleRelayer impl =
            new TruebitOracleRelayer(WATCH_TOWER, ILmsrGateway(makeAddr("gateway")), EXECUTION_TIMEOUT, ASYNC);
        TruebitOracleRelayer.InitParams memory params =
            TruebitOracleRelayer.InitParams({owner: OWNER, oracleFeeRecipient: address(0)});

        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.OracleFeeRecipientIsZeroAddress.selector));
        new ERC1967Proxy(address(impl), abi.encodeCall(TruebitOracleRelayer.initialize, (params)));
    }

    /// @dev Mirror the deployment-helper's WatchTower zero-address check inside the contract constructor,
    ///      keeping the invariant close to the state it protects.
    function test_Constructor_Reverts_ZeroWatchTower() external {
        vm.expectRevert(TruebitOracleRelayer.ZeroWatchTowerAddress.selector);
        new TruebitOracleRelayer(address(0), ILmsrGateway(makeAddr("gateway")), EXECUTION_TIMEOUT, ASYNC);
    }

    // ========== DEPLOYER: REUSED IMPLEMENTATION VALIDATION ==========

    function _matchingInitParams() private view returns (TruebitOracleRelayer.InitParams memory) {
        return TruebitOracleRelayer.InitParams({owner: OWNER, oracleFeeRecipient: ORACLE_FEE_RECIPIENT});
    }

    /// @dev External wrapper so vm.expectRevert reliably catches reverts raised inside the (internal)
    ///      deployer helper across a call boundary.
    function deployReusedExternal(
        address watchTower,
        ILmsrGateway gateway_,
        uint256 executionTimeout,
        bool async_,
        address implementation_,
        TruebitOracleRelayer.InitParams memory params
    ) external returns (TruebitOracleRelayer proxy, TruebitOracleRelayer impl) {
        return _deployTruebitOracleRelayerProxy(watchTower, gateway_, executionTimeout, async_, implementation_, params);
    }

    function test_DeployReusedImpl_Succeeds_WhenConfigMatches() external {
        ILmsrGateway gw = ILmsrGateway(makeAddr("gateway"));
        TruebitOracleRelayer impl = new TruebitOracleRelayer(WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC);

        (TruebitOracleRelayer proxy, TruebitOracleRelayer returnedImpl) = _deployTruebitOracleRelayerProxy(
            WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC, address(impl), _matchingInitParams()
        );

        assertEq(address(returnedImpl), address(impl), "should reuse the supplied implementation");
        assertEq(address(proxy.WATCHTOWER()), WATCH_TOWER, "proxy should read the reused impl's WatchTower");
    }

    function test_DeployReusedImpl_Reverts_NoCode() external {
        ILmsrGateway gw = ILmsrGateway(makeAddr("gateway"));
        address notAContract = makeAddr("NOT_A_CONTRACT");

        vm.expectRevert(
            abi.encodeWithSelector(TruebitOracleRelayerDeployer.ImplementationHasNoCode.selector, notAContract)
        );
        this.deployReusedExternal(WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC, notAContract, _matchingInitParams());
    }

    /// @dev WatchTower mismatch shown here; gateway / executionTimeout / async mismatches are structurally
    ///      identical (same immutable-comparison pattern in _validateReusedImplementation).
    function test_DeployReusedImpl_Reverts_WatchTowerMismatch() external {
        ILmsrGateway gw = ILmsrGateway(makeAddr("gateway"));
        address otherWatchTower = makeAddr("OTHER_WATCHTOWER");
        TruebitOracleRelayer impl = new TruebitOracleRelayer(otherWatchTower, gw, EXECUTION_TIMEOUT, ASYNC);

        vm.expectRevert(
            abi.encodeWithSelector(
                TruebitOracleRelayerDeployer.ImplementationWatchTowerMismatch.selector, WATCH_TOWER, otherWatchTower
            )
        );
        this.deployReusedExternal(WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC, address(impl), _matchingInitParams());
    }

    function test_DeployReusedImpl_Reverts_GatewayMismatch() external {
        ILmsrGateway gw = ILmsrGateway(makeAddr("gateway"));
        ILmsrGateway otherGateway = ILmsrGateway(makeAddr("OTHER_GATEWAY"));
        TruebitOracleRelayer impl = new TruebitOracleRelayer(WATCH_TOWER, otherGateway, EXECUTION_TIMEOUT, ASYNC);

        vm.expectRevert(
            abi.encodeWithSelector(
                TruebitOracleRelayerDeployer.ImplementationGatewayMismatch.selector, address(gw), address(otherGateway)
            )
        );
        this.deployReusedExternal(WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC, address(impl), _matchingInitParams());
    }

    function test_DeployReusedImpl_Reverts_ExecutionTimeoutMismatch() external {
        ILmsrGateway gw = ILmsrGateway(makeAddr("gateway"));
        uint256 otherTimeout = EXECUTION_TIMEOUT + 1;
        TruebitOracleRelayer impl = new TruebitOracleRelayer(WATCH_TOWER, gw, otherTimeout, ASYNC);

        vm.expectRevert(
            abi.encodeWithSelector(
                TruebitOracleRelayerDeployer.ImplementationExecutionTimeoutMismatch.selector,
                EXECUTION_TIMEOUT,
                otherTimeout
            )
        );
        this.deployReusedExternal(WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC, address(impl), _matchingInitParams());
    }

    function test_DeployReusedImpl_Reverts_AsyncMismatch() external {
        ILmsrGateway gw = ILmsrGateway(makeAddr("gateway"));
        bool otherAsync = !ASYNC;
        TruebitOracleRelayer impl = new TruebitOracleRelayer(WATCH_TOWER, gw, EXECUTION_TIMEOUT, otherAsync);

        vm.expectRevert(
            abi.encodeWithSelector(TruebitOracleRelayerDeployer.ImplementationAsyncMismatch.selector, ASYNC, otherAsync)
        );
        this.deployReusedExternal(WATCH_TOWER, gw, EXECUTION_TIMEOUT, ASYNC, address(impl), _matchingInitParams());
    }

    function test_SetOracleFeeRecipient_NewRecipientReceivesFee() external {
        // Custom setup with oracleFee > 0
        _useNewSender(OWNER);
        uint256 oracleFee = 1_000_000; // 1 USDC

        IERC20Metadata _token = IERC20Metadata(
            address(
                new MockToken({
                    name: "MockToken", symbol: "MOCK", _decimals: TOKEN_DECIMALS, admin: OWNER, initialAmount: 0
                })
            )
        );
        DelphiAddresses memory delphi = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: OWNER,
                marketCreationFeeRecipient: OWNER,
                marketCreationFee: oracleFee,
                keeperFee: 0,
                oracleFee: oracleFee,
                tradingFeesRecipientPct: TRADING_FEES_PCT,
                token: _token,
                gatewayOwner: OWNER
            })
        );
        LmsrGateway _gateway = delphi.gateway;
        LmsrMarket _impl = delphi.implementation;

        TruebitOracleRelayer _relayer = TruebitOracleRelayer(
            address(
                new ERC1967Proxy(
                    address(
                        new TruebitOracleRelayer(WATCH_TOWER, ILmsrGateway(address(_gateway)), EXECUTION_TIMEOUT, ASYNC)
                    ),
                    abi.encodeCall(
                        TruebitOracleRelayer.initialize,
                        (TruebitOracleRelayer.InitParams({owner: OWNER, oracleFeeRecipient: ORACLE_FEE_RECIPIENT}))
                    )
                )
            )
        );
        _gateway.setOracleRelayer(address(_relayer));

        // Deploy market and advance to AWAITING_SETTLEMENT
        _useNewSender(CREATOR);
        // uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();

        ILmsrMarketTypes.MarketConfig memory config = ILmsrMarketTypes.MarketConfig({
            outcomeCount: _impl.MIN_OUTCOME_COUNT(),
            b: _impl.MIN_B(),
            tradingFee: _impl.MIN_TRADING_FEE(),
            tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
            earliestResolveTime: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_RESOLVE_DELAY(),
            settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_RESOLVE_DELAY()
                + _impl.MIN_SETTLEMENT_WINDOW()
        });

        uint256 maxLoss = config.b.maxLoss(config.outcomeCount, _impl.TOKEN_DECIMAL_SCALER());
        uint256 marketCreationFee = _gateway.delphiFactory().MARKET_CREATION_FEE();
        uint256 initialDeposit = maxLoss + marketCreationFee;

        deal(address(_token), CREATOR, initialDeposit + oracleFee);
        _token.approve(address(_gateway.delphiFactory()), initialDeposit + oracleFee);

        ILmsrMarket marketProxy = ILmsrMarket(
            _gateway.delphiFactory()
                .deployNewMarketProxy({
                    initialDeposit_: initialDeposit,
                    newMarketConfig_: config,
                    newMarketMetadata: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")})
                })
        );
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Update recipient to a NEW address before the callback
        address newRecipient = makeAddr("newRecipient");
        _useNewSender(OWNER);
        _relayer.setOracleFeeRecipient(newRecipient);

        // Mock WatchTower and trigger resolution
        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        _gateway.resolveMarket(address(marketProxy));

        uint256 newRecipientBalanceBefore = _token.balanceOf(newRecipient);
        uint256 originalRecipientBalanceBefore = _token.balanceOf(ORACLE_FEE_RECIPIENT);

        // WatchTower delivers callback
        _useNewSender(WATCH_TOWER);
        _relayer.callbackTask(
            abi.encode(uint256(0)), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );

        // New recipient should receive the fee, original should receive nothing
        assertEq(
            _token.balanceOf(newRecipient) - newRecipientBalanceBefore,
            oracleFee,
            "new recipient should receive ORACLE_FEE"
        );
        assertEq(
            _token.balanceOf(ORACLE_FEE_RECIPIENT),
            originalRecipientBalanceBefore,
            "original recipient should receive nothing"
        );
    }

    // ========== INITIALIZE ==========

    function test_Initialize_RevertsIfCalledTwice() external {
        _setUp();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        relayer.initialize(TruebitOracleRelayer.InitParams({owner: OWNER, oracleFeeRecipient: ORACLE_FEE_RECIPIENT}));
    }

    // ========== CREATED AT ==========

    function test_CreatedAt_SetOnMarketCreation() external {
        uint256 deployTime = vm.getBlockTimestamp();
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();
        assertEq(marketProxy.createdAt(), deployTime, "createdAt should equal block.timestamp at deployment");
    }

    function test_CreatedAt_IsImmutableAfterCreation() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();
        uint256 createdAt = marketProxy.createdAt();

        vm.warp(block.timestamp + 365 days);

        assertEq(marketProxy.createdAt(), createdAt, "createdAt should not change after market creation");
    }

    // ========== RESOLVE MARKET ==========

    function test_ResolveMarket_BodyContainsMarketData() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        string memory expectedBody = string.concat(
            '{"metadata_path": "',
            marketProxy.getMarketMetadata().uri,
            '", "created_at": ',
            Strings.toString(marketProxy.createdAt()),
            ', "resolves_at": ',
            Strings.toString(marketProxy.getMarket().config.tradingDeadline),
            "}"
        );
        bytes memory expectedPayload =
            abi.encode(NAMESPACE, TASKNAME, METHOD, PATH, EXECUTION_TIMEOUT, ASYNC, expectedBody);
        bytes memory expectedCalldata = abi.encodeWithSelector(
            IWatchTower.requestExecution.selector,
            relayer.METHOD_SIGNATURE(),
            expectedPayload,
            bytes32(0), // codeHash is bytes32(0) by design — ignored by WatchTower for registered (API) tasks
            DOTypes.ExecutionType.API
        );

        // Use the same exact calldata for both mock and expectCall so Foundry tracks the call correctly
        vm.mockCall(WATCH_TOWER, expectedCalldata, abi.encode(FIRST_EXECUTION_ID));
        vm.expectCall(WATCH_TOWER, expectedCalldata);

        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));
    }

    /// @dev Correctness test: asserts the request body equals a HARDCODED literal (not rebuilt
    ///      from contract values), locking the exact JSON format the off-chain task consumes.
    ///      The format here was confirmed against a live integration: field names, the space
    ///      after each ':' and ',', metadata_path quoted, created_at/resolves_at as unquoted
    ///      numbers, and field order. If resolveMarket's concat drifts, this fails loudly.
    function test_ResolveMarket_BodyExactFormat() external {
        uint256 testStartTime = vm.getBlockTimestamp();
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();
        // tradingDeadline == createdAt + MIN_TRADING_WINDOW (== 1 + 30 == 31 with the foundry default block).
        uint256 expectedTradingDeadline = testStartTime + marketProxy.MIN_TRADING_WINDOW();

        // Sanity-check the literal's assumptions so a future timestamp/window/uri change
        // fails here with a clear message instead of an opaque calldata mismatch. These values are
        // baked into the hardcoded body below, so they must stay in lockstep with it.
        assertEq(marketProxy.getMarketMetadata().uri, "uri", "test assumes uri == 'uri'");
        assertEq(marketProxy.createdAt(), 1, "test assumes createdAt == 1 (foundry default block)");
        assertEq(expectedTradingDeadline, 31, "test assumes tradingDeadline == 31");
        assertEq(
            marketProxy.getMarket().config.tradingDeadline,
            expectedTradingDeadline,
            "test assumes tradingDeadline == 31"
        );

        // Hardcoded expected body — NOT built via the contract's string.concat.
        string memory expectedBody = '{"metadata_path": "uri", "created_at": 1, "resolves_at": 31}';

        bytes memory expectedPayload =
            abi.encode(NAMESPACE, TASKNAME, METHOD, PATH, EXECUTION_TIMEOUT, ASYNC, expectedBody);
        bytes memory expectedCalldata = abi.encodeWithSelector(
            IWatchTower.requestExecution.selector,
            relayer.METHOD_SIGNATURE(),
            expectedPayload,
            bytes32(0), // codeHash is bytes32(0) by design — ignored by WatchTower for registered (API) tasks
            DOTypes.ExecutionType.API
        );

        vm.mockCall(WATCH_TOWER, expectedCalldata, abi.encode(FIRST_EXECUTION_ID));
        vm.expectCall(WATCH_TOWER, expectedCalldata);

        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));
    }

    function test_ResolveMarket_Reverts_CallerIsNotGateway(address caller) external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.assume(caller != address(gateway));
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.CallerIsNotGateway.selector, caller));
        relayer.resolveMarket(address(marketProxy));
    }

    function test_ResolveMarket_StoresPendingRequest() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        assertEq(relayer.pendingRequests(FIRST_EXECUTION_ID), address(0), "no pending request before resolve");

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        assertEq(relayer.pendingRequests(FIRST_EXECUTION_ID), address(marketProxy), "pending request should be stored");
    }

    function test_ResolveMarket_EmitsResolutionRequested() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();
        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        vm.expectEmit(true, true, false, false, address(relayer));
        emit TruebitOracleRelayer.ResolutionRequested(address(marketProxy), FIRST_EXECUTION_ID);

        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));
    }

    /// @dev A malicious/buggy WatchTower returning a duplicate execution id for a second market must NOT
    ///      overwrite (orphan) the first market's pending request. The second resolution reverts, the
    ///      first market's entry survives, and the first market can still be settled via its callback.
    function test_ResolveMarket_Reverts_DuplicateExecutionId() external {
        _setUp();
        ILmsrMarket marketA = _createMarket();
        ILmsrMarket marketB = _createMarket();

        // Both markets are created in the same block, so they share an earliestResolveTime: this single
        // warp makes both of them resolvable.
        vm.warp(marketA.getMarket().config.earliestResolveTime);

        // WatchTower returns the SAME execution id for both requests.
        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );

        address keeper = makeAddr("keeper");

        // First resolution records pendingRequests[id] = marketA.
        _useNewSender(keeper);
        gateway.resolveMarket(address(marketA));
        assertEq(relayer.pendingRequests(FIRST_EXECUTION_ID), address(marketA), "marketA should be recorded");

        // Second resolution gets the duplicate id from the WatchTower → relayer reverts → the whole
        // gateway.resolveMarket tx rolls back (settlementLocked[marketB] is reverted too).
        _useNewSender(keeper);
        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.DuplicateExecutionId.selector, FIRST_EXECUTION_ID));
        gateway.resolveMarket(address(marketB));

        // marketA's entry survives the collision attempt; marketB is left retryable (not locked, not orphaned).
        assertEq(relayer.pendingRequests(FIRST_EXECUTION_ID), address(marketA), "marketA entry must stay intact");
        assertFalse(gateway.settlementLocked(address(marketB)), "marketB should remain unlocked / retryable");

        // marketA can still be completed through its original request.
        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(
            abi.encode(uint256(0)), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );
        assertEq(
            uint8(marketA.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.SETTLED),
            "marketA should still settle after the duplicate was rejected"
        );
    }

    // ========== CALLBACK TASK ==========

    function test_CallbackTask_Reverts_NotWatchTower(address caller) external {
        _setUp();

        vm.assume(caller != WATCH_TOWER);
        vm.assume(caller != address(0));

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.NotWatchTower.selector, caller));
        relayer.callbackTask(bytes(""), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), "");
    }

    /// @dev Backend-requested: callbackTask emits CallbackReceived carrying the full payload (notably the
    ///      transcripts) for off-chain consumers. Emitted in the Effects phase, before the settle interaction.
    function test_CallbackTask_EmitsCallbackReceived() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        // Resolve through the gateway (sets settlementLocked + stores the pending request) rather than calling
        // the relayer directly — forward-compatible with the AS-2 settlement-lock guard once it lands.
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        string[] memory transcripts = new string[](2);
        transcripts[0] = "transcript-a";
        transcripts[1] = "transcript-b";
        bytes memory resultData = abi.encode(uint256(0));

        // Check both topics and the full (non-indexed) data payload.
        vm.expectEmit(true, true, false, true, address(relayer));
        emit TruebitOracleRelayer.CallbackReceived(
            address(marketProxy), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), resultData, transcripts
        );

        _useNewSender(WATCH_TOWER);
        // 5th arg (callbackMessageDetails) is part of the WatchTower interface but unused on-chain.
        relayer.callbackTask(
            resultData, transcripts, FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), "unused"
        );

        // Sanity: the callback still settled the market (event is emitted before, not instead of, settlement).
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.SETTLED),
            "market should be SETTLED after the successful callback"
        );
    }

    function test_CallbackTask_UnknownExecutionId_Reverts(uint256 unknownId) external {
        _setUp();

        // Ensure no pending request exists for this ID
        vm.assume(relayer.pendingRequests(unknownId) == address(0));

        // Revert so the WatchTower's try/catch emits CallbackFailed, not RequestFulfilled
        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.UnknownExecutionId.selector, unknownId));

        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(bytes(""), new string[](0), unknownId, 0, "");
    }

    function test_CallbackTask_NonSuccessStatus_FailsMarket(uint8 status) external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        // Bound to valid enum range (0=SUCCESS, 1=FAILED, 2=ERROR, 3=EXCEEDED, 4=CODE_HASH_MISMATCH)
        // and exclude SUCCESS
        status = uint8(
            bound(status, uint8(DOTypes.ExecutionStatus.FAILED), uint8(DOTypes.ExecutionStatus.CODE_HASH_MISMATCH))
        );

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        vm.expectEmit(true, false, false, false, address(gateway));
        emit ILmsrGateway.GatewayMarketFailed(address(marketProxy));
        // status is fuzzed — check topics only, not data (executionStatus varies)
        vm.expectEmit(true, true, false, false, address(relayer));
        emit TruebitOracleRelayer.ResolutionFailed(
            address(marketProxy), FIRST_EXECUTION_ID, TruebitOracleRelayer.FailureReason.EXECUTION_FAILED, 0
        );

        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(bytes(""), new string[](0), FIRST_EXECUTION_ID, status, "");

        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.FAILED), "market should be FAILED"
        );
    }

    function test_CallbackTask_OutOfRangeStatus_FailsMarket(uint8 status) external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        // Only fuzz values outside the defined enum range (> CODE_HASH_MISMATCH = 4)
        vm.assume(status > uint8(DOTypes.ExecutionStatus.CODE_HASH_MISMATCH));

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        vm.expectEmit(true, false, false, false, address(gateway));
        emit ILmsrGateway.GatewayMarketFailed(address(marketProxy));
        // status is fuzzed — check topics only, not data (executionStatus varies)
        vm.expectEmit(true, true, false, false, address(relayer));
        emit TruebitOracleRelayer.ResolutionFailed(
            address(marketProxy), FIRST_EXECUTION_ID, TruebitOracleRelayer.FailureReason.EXECUTION_FAILED, 0
        );

        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(bytes(""), new string[](0), FIRST_EXECUTION_ID, status, "");

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.FAILED),
            "market should be FAILED for out-of-range status"
        );
    }

    function test_CallbackTask_MalformedResultData_FailsMarket(uint8 badLength) external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();
        vm.assume(badLength != 32);

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        vm.expectEmit(true, false, false, false, address(gateway));
        emit ILmsrGateway.GatewayMarketFailed(address(marketProxy));
        vm.expectEmit(true, true, false, true, address(relayer));
        emit TruebitOracleRelayer.ResolutionFailed(
            address(marketProxy), FIRST_EXECUTION_ID, TruebitOracleRelayer.FailureReason.MALFORMED_RESULT, 0
        );

        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(
            new bytes(badLength), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );

        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.FAILED), "market should be FAILED"
        );
    }

    function test_CallbackTask_OutOfBoundsOutcomeIdx_FailsMarket(uint256 outcomeIdx) external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();
        outcomeIdx = bound(outcomeIdx, implementation.MIN_OUTCOME_COUNT(), type(uint256).max);

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        vm.expectEmit(true, false, false, false, address(gateway));
        emit ILmsrGateway.GatewayMarketFailed(address(marketProxy));
        vm.expectEmit(true, true, false, true, address(relayer));
        emit TruebitOracleRelayer.ResolutionFailed(
            address(marketProxy), FIRST_EXECUTION_ID, TruebitOracleRelayer.FailureReason.INVALID_OUTCOME, 0
        );

        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(
            abi.encode(outcomeIdx), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );

        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.FAILED), "market should be FAILED"
        );
    }

    function test_CallbackTask_Success_ClearsExecutionId() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        assertEq(
            relayer.pendingRequests(FIRST_EXECUTION_ID),
            address(marketProxy),
            "pending request should exist before callback"
        );

        // Deliver any failure callback — should clear the ID regardless
        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(bytes(""), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.FAILED), "");

        assertEq(
            relayer.pendingRequests(FIRST_EXECUTION_ID), address(0), "pending request should be cleared after callback"
        );
    }

    /// @dev Late-callback timing boundary. A WatchTower callback that arrives after
    ///      settlementDeadline (market already EXPIRED) must NOT settle the market: the downstream
    ///      gateway.settleMarket carries ifStatus(AWAITING_SETTLEMENT) and reverts, so the callback is
    ///      rejected and its CEI delete is rolled back (the pending request survives). The market stays
    ///      EXPIRED and is recovered via pro-rata liquidation rather than outcome-based settlement —
    ///      a deliberate liveness tradeoff, pinned here so future changes can't silently alter it.
    function test_CallbackTask_AfterSettlementDeadline_DoesNotSettle() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        // Warp past the settlement deadline so the market has expired before the callback arrives.
        vm.warp(marketProxy.getMarket().config.settlementDeadline + 1);
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.EXPIRED),
            "market should be EXPIRED before the late callback"
        );

        // A SUCCESS callback with a valid outcome arriving now must revert (market no longer AWAITING_SETTLEMENT).
        _useNewSender(WATCH_TOWER);
        vm.expectPartialRevert(ILmsrMarketErrors.WrongMarketStatus.selector);
        relayer.callbackTask(
            abi.encode(uint256(0)), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );

        // The market is untouched: still EXPIRED (not SETTLED), and the pending request survived the rollback.
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.EXPIRED),
            "market should remain EXPIRED after the rejected late callback"
        );
        assertEq(
            relayer.pendingRequests(FIRST_EXECUTION_ID),
            address(marketProxy),
            "pending request should survive the rolled-back late callback"
        );
    }

    function test_CallbackTask_CEI_ReplayPrevented() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        // First callback — fails market and clears the ID
        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(bytes(""), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.FAILED), "");

        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.FAILED),
            "market should be FAILED after first callback"
        );

        // Second callback with same ID — reverts because ID was already deleted
        vm.expectRevert(abi.encodeWithSelector(TruebitOracleRelayer.UnknownExecutionId.selector, FIRST_EXECUTION_ID));

        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(bytes(""), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.FAILED), "");

        // Market status must not change — replay had no effect
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.FAILED),
            "market status should not change on replay attempt"
        );
    }

    function test_CallbackTask_Success() external {
        // Custom setup with oracleFee > 0 to assert real balance changes
        _useNewSender(OWNER);
        uint256 oracleFee = 1_000_000; // 1 USDC (6 decimals)

        IERC20Metadata _token = IERC20Metadata(
            address(
                new MockToken({
                    name: "MockToken", symbol: "MOCK", _decimals: TOKEN_DECIMALS, admin: OWNER, initialAmount: 0
                })
            )
        );
        DelphiAddresses memory delphi = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: OWNER,
                marketCreationFeeRecipient: OWNER,
                marketCreationFee: oracleFee,
                keeperFee: 0,
                oracleFee: oracleFee,
                tradingFeesRecipientPct: TRADING_FEES_PCT,
                token: _token,
                gatewayOwner: OWNER
            })
        );

        LmsrGateway _gateway = delphi.gateway;
        LmsrMarket _impl = delphi.implementation;

        TruebitOracleRelayer _relayer = TruebitOracleRelayer(
            address(
                new ERC1967Proxy(
                    address(
                        new TruebitOracleRelayer(WATCH_TOWER, ILmsrGateway(address(_gateway)), EXECUTION_TIMEOUT, ASYNC)
                    ),
                    abi.encodeCall(
                        TruebitOracleRelayer.initialize,
                        (TruebitOracleRelayer.InitParams({owner: OWNER, oracleFeeRecipient: ORACLE_FEE_RECIPIENT}))
                    )
                )
            )
        );
        _gateway.setOracleRelayer(address(_relayer));

        // Deploy market and advance to AWAITING_SETTLEMENT
        _useNewSender(CREATOR);
        // uint256 initialDeposit = _impl.MIN_INITIAL_DEPOSIT();

        ILmsrMarketTypes.MarketConfig memory config = ILmsrMarketTypes.MarketConfig({
            outcomeCount: _impl.MIN_OUTCOME_COUNT(),
            b: _impl.MIN_B(),
            tradingFee: _impl.MIN_TRADING_FEE(),
            tradingDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW(),
            earliestResolveTime: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_RESOLVE_DELAY(),
            settlementDeadline: block.timestamp + _impl.MIN_TRADING_WINDOW() + _impl.MIN_RESOLVE_DELAY()
                + _impl.MIN_SETTLEMENT_WINDOW()
        });

        uint256 maxLoss = config.b.maxLoss(config.outcomeCount, _impl.TOKEN_DECIMAL_SCALER());
        uint256 marketCreationFee = _gateway.delphiFactory().MARKET_CREATION_FEE();
        uint256 initialDeposit = maxLoss + marketCreationFee;

        deal(address(_token), CREATOR, initialDeposit + oracleFee);
        _token.approve(address(_gateway.delphiFactory()), initialDeposit + oracleFee);

        ILmsrMarket marketProxy = ILmsrMarket(
            _gateway.delphiFactory()
                .deployNewMarketProxy({
                    initialDeposit_: initialDeposit,
                    newMarketConfig_: config,
                    newMarketMetadata: IDelphiMarket.VerifiableUri({uri: "uri", uriContentHash: keccak256("uri")})
                })
        );
        vm.warp(marketProxy.getMarket().config.tradingDeadline + 1);

        // Record recipient balance before callback to assert exact oracle fee transfer
        uint256 recipientBalanceBefore = _token.balanceOf(ORACLE_FEE_RECIPIENT);

        // Mock WatchTower and trigger resolution via gateway
        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );

        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        vm.expectEmit(true, true, false, false, address(_relayer));
        emit TruebitOracleRelayer.ResolutionRequested(address(marketProxy), FIRST_EXECUTION_ID);
        _gateway.resolveMarket(address(marketProxy));

        // WatchTower delivers callback with winning outcome 0
        _useNewSender(WATCH_TOWER);
        _relayer.callbackTask(
            abi.encode(uint256(0)), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );

        // Assert oracle fee landed in the recipient's wallet
        // (market balance also decreases by the settlement payout so we cannot assert its exact delta here)
        assertEq(
            _token.balanceOf(ORACLE_FEE_RECIPIENT) - recipientBalanceBefore,
            oracleFee,
            "oracle fee recipient should receive ORACLE_FEE"
        );

        // Assert market settled
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.SETTLED), "market should be SETTLED"
        );
    }

    /// @dev Full happy path with BOTH fees non-zero: a correct settlement must pay the keeper fee to
    ///      the keeper (at resolve) AND the oracle fee to the treasury (at settle), in one flow.
    function testFuzz_FullSettlement_DisbursesBothFees(
        ILmsrMarket.MarketConfig calldata marketConfig,
        uint256 initialDeposit
    ) external {
        // Setup
        _setUp();

        // Deploy market
        ILmsrMarket marketProxy = _boundAndDeployMarket({
            marketConfig: marketConfig,
            deployment: DelphiAddresses({gateway: gateway, implementation: implementation, factory: factory}),
            token: token,
            initialDeposit: initialDeposit
        });

        // Get keeper and oracle fee
        uint256 keeperFee = implementation.KEEPER_FEE();
        uint256 oracleFee = implementation.ORACLE_FEE();

        // Warp to earliest resolve time
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);

        // Get token balances before
        uint256 keeperTokensBefore = token.balanceOf(KEEPER);
        uint256 oracleFeeRecipientTokensBefore = token.balanceOf(ORACLE_FEE_RECIPIENT);

        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );

        // Keeper resolves → keeper fee paid here
        _useNewSender(KEEPER);
        gateway.resolveMarket(address(marketProxy));
        assertEq(token.balanceOf(KEEPER) - keeperTokensBefore, keeperFee, "keeper should receive KEEPER_FEE at resolve");

        // WatchTower delivers SUCCESS → settle → oracle fee paid to treasury
        _useNewSender(WATCH_TOWER);
        relayer.callbackTask(
            abi.encode(uint256(0)), new string[](0), FIRST_EXECUTION_ID, uint8(DOTypes.ExecutionStatus.SUCCESS), ""
        );

        assertEq(
            token.balanceOf(ORACLE_FEE_RECIPIENT) - oracleFeeRecipientTokensBefore,
            oracleFee,
            "treasury should receive ORACLE_FEE at settle"
        );
        assertEq(
            uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.SETTLED), "market should be SETTLED"
        );
    }

    // ========== GET TASK SOURCE ==========

    /// @dev getTaskSource is never called by the WatchTower for registered (API) tasks; it exists only to
    ///      satisfy IBaseTBContract. Lock the stub's empty return so it can't silently drift.
    function test_GetTaskSource_ReturnsEmpty() external {
        _setUp();
        assertEq(relayer.getTaskSource(), "", "getTaskSource should return empty for registered API tasks");
    }

    // ========== UUPS UPGRADE ==========

    /// @dev Proves the ERC-7201 storage layout is upgrade-safe: V1 state (namespaced struct + Ownable) is
    ///      preserved across an upgrade, and a V2 that appends a new var (its own ERC-7201 namespace) reads
    ///      and writes without colliding with existing storage.
    function test_Upgrade_PreservesStorageAndOwner() external {
        ILmsrMarket marketProxy = _setUpMarketAwaitingSettlement();

        // Populate V1 storage: a pending request (ERC-7201 struct) alongside oracleFeeRecipient + owner.
        vm.mockCall(
            WATCH_TOWER, abi.encodeWithSelector(IWatchTower.requestExecution.selector), abi.encode(FIRST_EXECUTION_ID)
        );
        _useNewSender(makeAddr("keeper"));
        vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        gateway.resolveMarket(address(marketProxy));

        assertEq(relayer.pendingRequests(FIRST_EXECUTION_ID), address(marketProxy), "precondition: pending request set");
        assertEq(relayer.oracleFeeRecipient(), ORACLE_FEE_RECIPIENT, "precondition: recipient set");
        assertEq(relayer.owner(), OWNER, "precondition: owner set");

        // Upgrade to V2 (appends a storage var via its own ERC-7201 namespace).
        TruebitOracleRelayerV2 implV2 =
            new TruebitOracleRelayerV2(WATCH_TOWER, ILmsrGateway(address(gateway)), EXECUTION_TIMEOUT, ASYNC);
        _useNewSender(OWNER);
        relayer.upgradeToAndCall(address(implV2), "");

        // (a) V1 storage preserved across the upgrade.
        assertEq(
            relayer.pendingRequests(FIRST_EXECUTION_ID), address(marketProxy), "pendingRequests preserved after upgrade"
        );
        assertEq(relayer.oracleFeeRecipient(), ORACLE_FEE_RECIPIENT, "oracleFeeRecipient preserved after upgrade");
        assertEq(relayer.owner(), OWNER, "owner preserved after upgrade");

        // (b) new appended var works and does not collide with existing storage.
        TruebitOracleRelayerV2 upgraded = TruebitOracleRelayerV2(address(relayer));
        assertEq(upgraded.version(), 2, "implementation should be V2");
        assertEq(upgraded.appendedValue(), 0, "appended var starts zero");
        upgraded.setAppendedValue(42);
        assertEq(upgraded.appendedValue(), 42, "appended var should be writable");

        // existing storage still intact after writing the new var (no overlap).
        assertEq(
            relayer.pendingRequests(FIRST_EXECUTION_ID), address(marketProxy), "pendingRequests intact after new write"
        );
        assertEq(relayer.oracleFeeRecipient(), ORACLE_FEE_RECIPIENT, "oracleFeeRecipient intact after new write");
    }

    function test_Upgrade_Reverts_NotOwner(address caller) external {
        _setUp();
        vm.assume(caller != OWNER);
        vm.assume(caller != address(0));

        TruebitOracleRelayerV2 implV2 =
            new TruebitOracleRelayerV2(WATCH_TOWER, ILmsrGateway(address(gateway)), EXECUTION_TIMEOUT, ASYNC);

        _useNewSender(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        relayer.upgradeToAndCall(address(implV2), "");
    }
}
