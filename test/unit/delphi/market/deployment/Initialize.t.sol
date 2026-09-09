// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {ILmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {IDelphiMarket} from "src/IDelphiMarket.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract LmsrMarket_Initialize_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;
    using Clones for address;

    // ===== CALLDATA =====
    function testFuzz_Initialize_RandomCalldata_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        address marketCreator
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Expect revert
        vm.expectRevert();

        // Initialize market proxy with a zero market creator
        marketProxy.initialize({
            marketCreator_: marketCreator, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    // ===== MARKET CREATOR =====
    function testFuzz_Initialize_MarketCreatorIsZeroAddress_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.MarketCreatorIsZeroAddress.selector));

        // Initialize market proxy with a zero market creator
        marketProxy.initialize({
            marketCreator_: address(0), newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    // ===== LMSR CONFIG =====
    function testFuzz_Initialize_LmsrConfig_OutcomeCountIsTooLow_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Set outcome count too low
        marketConfig.outcomeCount = deployment.implementation.MIN_OUTCOME_COUNT() - 1;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.OutcomeCountIsTooLow.selector,
                marketConfig.outcomeCount,
                deployment.implementation.MIN_OUTCOME_COUNT()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_OutcomeCountIsTooHigh_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Set outcome count too high
        marketConfig.outcomeCount = deployment.implementation.MAX_OUTCOME_COUNT() + 1;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.OutcomeCountIsTooHigh.selector,
                marketConfig.outcomeCount,
                deployment.implementation.MAX_OUTCOME_COUNT()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_BIsTooLow_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Set b too low
        marketConfig.b = deployment.implementation.MIN_B() - 1;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.BIsTooLow.selector, marketConfig.b, deployment.implementation.MIN_B()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_BIsTooHigh_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Set b too high
        marketConfig.b = deployment.implementation.MAX_B() + 1;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.BIsTooHigh.selector, marketConfig.b, deployment.implementation.MAX_B()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_TradingFeeIsTooLow_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Set trading fee too low
        marketConfig.tradingFee = deployment.implementation.MIN_TRADING_FEE() - 1;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.TradingFeeIsTooLow.selector,
                marketConfig.tradingFee,
                deployment.implementation.MIN_TRADING_FEE()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_TradingFeeIsTooHigh_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Set trading fee too high
        marketConfig.tradingFee = deployment.implementation.MAX_TRADING_FEE() + 1;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.TradingFeeIsTooHigh.selector,
                marketConfig.tradingFee,
                deployment.implementation.MAX_TRADING_FEE()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_TradingDeadlineNotInFuture_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Set trading deadline not in future
        marketConfig.tradingDeadline = block.timestamp;

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.TradingDeadlineIsNotInTheFuture.selector,
                marketConfig.tradingDeadline,
                block.timestamp
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_TradingWindowIsTooShort_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Make trading window too short
        // tradingWindow < MIN_TRADING_WINDOW
        // marketConfig.tradingDeadline - block.timestamp < implementation.MIN_TRADING_WINDOW()
        // marketConfig.tradingDeadline < block.timestamp + implementation.MIN_TRADING_WINDOW()
        marketConfig.tradingDeadline = bound(
            marketConfig.tradingDeadline,
            block.timestamp + 1,
            block.timestamp + deployment.implementation.MIN_TRADING_WINDOW() - 1
        );

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.TradingWindowIsTooShort.selector,
                marketConfig.tradingDeadline - block.timestamp,
                deployment.implementation.MIN_TRADING_WINDOW()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_TradingWindowIsTooLong_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Make trading window too short
        // tradingWindow > MAX_TRADING_WINDOW
        // marketConfig.tradingDeadline - block.timestamp > implementation.MAX_TRADING_WINDOW()
        // marketConfig.tradingDeadline > block.timestamp + implementation.MAX_TRADING_WINDOW()
        marketConfig.tradingDeadline = bound(
            marketConfig.tradingDeadline,
            block.timestamp + deployment.implementation.MAX_TRADING_WINDOW() + 1,
            type(uint256).max
        );

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.TradingWindowIsTooLong.selector,
                marketConfig.tradingDeadline - block.timestamp,
                deployment.implementation.MAX_TRADING_WINDOW()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_EarliestResolveTimeIsNotAfterTheTradingDeadline_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Set earliestResolveTime <= trading deadline
        marketConfig.earliestResolveTime = bound(marketConfig.earliestResolveTime, 0, marketConfig.tradingDeadline);

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.EarliestResolveTimeIsNotAfterTheTradingDeadline.selector,
                marketConfig.earliestResolveTime,
                marketConfig.tradingDeadline
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_ResolveDelayIsTooLow_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Make resolve delay too low
        // resolveDelay < MIN_RESOLVE_DELAY
        // marketConfig.earliestResolveTime - marketConfig.tradingDeadline < implementation.MIN_RESOLVE_DELAY()
        // marketConfig.earliestResolveTime < marketConfig.tradingDeadline + implementation.MIN_RESOLVE_DELAY()
        marketConfig.earliestResolveTime = bound(
            marketConfig.earliestResolveTime,
            marketConfig.tradingDeadline + 1,
            marketConfig.tradingDeadline + deployment.implementation.MIN_RESOLVE_DELAY() - 1
        );

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.ResolveDelayIsTooLow.selector,
                marketConfig.earliestResolveTime - marketConfig.tradingDeadline,
                deployment.implementation.MIN_RESOLVE_DELAY()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_ResolveDelayIsTooHigh_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Make resolve delay too high
        // resolveDelay > MAX_RESOLVE_DELAY
        // marketConfig.earliestResolveTime - marketConfig.tradingDeadline > implementation.MAX_RESOLVE_DELAY()
        // marketConfig.earliestResolveTime > marketConfig.tradingDeadline + implementation.MAX_RESOLVE_DELAY()
        marketConfig.earliestResolveTime = bound(
            marketConfig.earliestResolveTime,
            marketConfig.tradingDeadline + deployment.implementation.MAX_RESOLVE_DELAY() + 1,
            type(uint256).max
        );

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.ResolveDelayIsTooHigh.selector,
                marketConfig.earliestResolveTime - marketConfig.tradingDeadline,
                deployment.implementation.MAX_RESOLVE_DELAY()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_SettlementDeadlineIsNotAfterTheEarliestResolveTime_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Set settlementDeadline <= earliestResolveTime
        marketConfig.settlementDeadline = bound(marketConfig.settlementDeadline, 0, marketConfig.earliestResolveTime);

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.SettlementDeadlineIsNotAfterTheEarliestResolveTime.selector,
                marketConfig.settlementDeadline,
                marketConfig.earliestResolveTime
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_SettlementWindowIsTooShort_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Make settlement window too short
        // settlementWindow < MIN_SETTLEMENT_WINDOW
        // marketConfig.settlementDeadline - marketConfig.earliestResolveTime < implementation.MIN_SETTLEMENT_WINDOW()
        // marketConfig.settlementDeadline < marketConfig.earliestResolveTime + implementation.MIN_SETTLEMENT_WINDOW()
        marketConfig.settlementDeadline = bound(
            marketConfig.settlementDeadline,
            marketConfig.earliestResolveTime + 1,
            marketConfig.earliestResolveTime + deployment.implementation.MIN_SETTLEMENT_WINDOW() - 1
        );

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.SettlementWindowIsTooShort.selector,
                marketConfig.settlementDeadline - marketConfig.earliestResolveTime,
                deployment.implementation.MIN_SETTLEMENT_WINDOW()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    function testFuzz_Initialize_LmsrConfig_SettlementWindowIsTooLong_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Make settlement window too long
        // settlementWindow > MAX_SETTLEMENT_WINDOW
        // marketConfig.settlementDeadline - marketConfig.earliestResolveTime > implementation.MAX_SETTLEMENT_WINDOW()
        // marketConfig.settlementDeadline > marketConfig.earliestResolveTime + implementation.MAX_SETTLEMENT_WINDOW()
        marketConfig.settlementDeadline = bound(
            marketConfig.settlementDeadline,
            marketConfig.earliestResolveTime + deployment.implementation.MAX_SETTLEMENT_WINDOW() + 1,
            type(uint256).max
        );

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                ILmsrMarketErrors.SettlementWindowIsTooLong.selector,
                marketConfig.settlementDeadline - marketConfig.earliestResolveTime,
                deployment.implementation.MAX_SETTLEMENT_WINDOW()
            )
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    // ===== VERIFIABLE URI =====
    function testFuzz_Initialize_VerifiableUri_UriIsEmpty_Reverts(
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

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.UriIsEmpty.selector));

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR,
            newMarketConfig_: marketConfig,
            newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: "", uriContentHash: VERIFIABLE_URI_CONTENT_HASH})
        });
    }

    function testFuzz_Initialize_VerifiableUri_UriContentHashIsZero_Reverts(
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

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, type(uint256).max);

        // Approve factory to spend initial deposit
        token.approve(address(deployment.factory), initialDeposit);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.UriContentHashIsZero.selector));

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR,
            newMarketConfig_: marketConfig,
            newMarketMetadata_: IDelphiMarket.VerifiableUri({uri: VERIFIABLE_URI, uriContentHash: bytes32(0)})
        });
    }

    // ===== TOKEN BALANCE =====

    function testFuzz_Initialize_TokenBalanceIsLessThanMaxLoss_Reverts(
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

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Calculate max loss
        uint256 maxLoss =
            marketConfig.b.maxLoss(marketConfig.outcomeCount, deployment.implementation.TOKEN_DECIMAL_SCALER());

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, 1, maxLoss - 1);

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Approve factory to spend initial deposit
        token.approve(address(deployment.factory), initialDeposit);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrMarketErrors.TokenBalanceIsLessThanMaxLoss.selector, initialDeposit, maxLoss)
        );

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });
    }

    // ===== SUCCESS =====

    function testFuzz_Initialize_Success(
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

        // Bound market config
        marketConfig = _boundMarketConfig(deployment.implementation, marketConfig);

        // Calculate max loss
        uint256 maxLoss =
            marketConfig.b.maxLoss(marketConfig.outcomeCount, deployment.implementation.TOKEN_DECIMAL_SCALER());

        // Bound initial deposit (at least max loss)
        initialDeposit = bound(initialDeposit, maxLoss, _oneTrillionTokens(token));

        // Deal initial deposit to creator
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Clone implementation
        marketProxy = ILmsrMarket(address(deployment.implementation).clone());

        // Transfer initial deposit to market proxy
        token.transfer(address(marketProxy), initialDeposit);

        // Initialize market proxy
        marketProxy.initialize({
            marketCreator_: MARKET_CREATOR, newMarketConfig_: marketConfig, newMarketMetadata_: _dummyVerifiableUri()
        });

        // Get market
        ILmsrMarket.Market memory market = marketProxy.getMarket();

        // Validate initialization immutables
        assertEq(marketProxy.marketCreator(), MARKET_CREATOR, "marketCreator mismatch");
        assertEq(marketProxy.createdAt(), block.timestamp, "createdAt mismatch");

        // Validate market metadata
        IDelphiMarket.VerifiableUri memory metadata = marketProxy.getMarketMetadata();
        assertEq(metadata.uri, VERIFIABLE_URI, "uri mismatch");
        assertEq(metadata.uriContentHash, VERIFIABLE_URI_CONTENT_HASH, "uriContentHash mismatch");

        // Validate market config
        assertEq(market.config.outcomeCount, marketConfig.outcomeCount, "outcomeCount mismatch");
        assertEq(market.config.b, marketConfig.b, "b mismatch");
        assertEq(market.config.tradingFee, marketConfig.tradingFee, "tradingFee mismatch");
        assertEq(market.config.tradingDeadline, marketConfig.tradingDeadline, "tradingDeadline mismatch");
        assertEq(market.config.settlementDeadline, marketConfig.settlementDeadline, "settlementDeadline mismatch");

        // Validate market state
        assertEq(market.pool, initialDeposit, "pool mismatch");
        assertEq(market.tradingFees, 0, "tradingFees mismatch");
        assertEq(market.expSum, marketConfig.outcomeCount * 1e18, "expSum mismatch");
        assertEq(market.winningOutcomeIdx, type(uint256).max, "winningOutcomeIdx mismatch");

        // Validate market status
        assertEq(uint8(marketProxy.marketStatus()), uint8(ILmsrMarketTypes.MarketStatus.OPEN), "status != OPEN");
    }
}
