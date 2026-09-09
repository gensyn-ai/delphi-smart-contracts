// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {LmsrMarket, ILmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ILmsrMarketErrors} from "src/lmsr/implementation/ILmsrMarketErrors.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

contract DelphiFactory_DeployNewMarketProxy_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Libraries
    using LmsrMath for uint256;

    // Tests
    function testFuzz_DeployNewMarketProxy_InsufficientAllowance_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        LmsrMarket.MarketConfig memory marketConfig,
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

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                deployment.factory,
                token.allowance(MARKET_CREATOR, address(deployment.factory)),
                initialDeposit
            )
        );

        // Deploy new market proxy
        deployment.factory
            .deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketConfig_: marketConfig,
                newMarketMetadata_: _dummyVerifiableUri()
            });
    }

    function testFuzz_DeployNewMarketProxy_InsufficientBalance_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        LmsrMarket.MarketConfig memory marketConfig,
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

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Approve factory to spend initial deposit
        token.approve(address(deployment.factory), initialDeposit);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                MARKET_CREATOR,
                token.balanceOf(MARKET_CREATOR),
                initialDeposit
            )
        );

        // Deploy new market proxy
        deployment.factory
            .deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketConfig_: marketConfig,
                newMarketMetadata_: _dummyVerifiableUri()
            });
    }

    function testFuzz_DeployNewMarketProxy_GatewayOracleRelayerNotSet_Reverts(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        LmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit
    ) external {
        // Deploy Token
        token = _boundAndDeployToken(tokenDecimals);

        // Override delphi config token (so that token is used in delphi deployment)
        delphiConfig.token = token;

        // Deploy Delphi WITHOUT wiring an oracle relayer on the gateway
        deployment = _boundAndDeployDelphi(delphiConfig);

        // Bound initial deposit
        // Note: The oracle relayer check fires before the config and funding checks,
        //       so neither the market config nor the deposit amount needs to be valid.
        initialDeposit = bound(initialDeposit, 0, _oneTrillionTokens(token));

        // Deal initial deposit to market creator (so the factory's transferFrom succeeds)
        deal(address(token), MARKET_CREATOR, initialDeposit);

        // Switch to creator
        _useNewSender(MARKET_CREATOR);

        // Approve factory to spend initial deposit
        token.approve(address(deployment.factory), initialDeposit);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMarketErrors.GatewayOracleRelayerNotSet.selector));

        // Deploy new market proxy
        deployment.factory
            .deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketConfig_: marketConfig,
                newMarketMetadata_: _dummyVerifiableUri()
            });
    }

    // Todo: Break this up into multiple tests
    function testFuzz_DeployNewMarketProxy_Success(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        LmsrMarket.MarketConfig memory marketConfig,
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
        marketConfig = _boundMarketConfig({implementation: deployment.implementation, config: marketConfig});

        // Calculate max loss
        uint256 maxLoss =
            marketConfig.b.maxLoss(marketConfig.outcomeCount, deployment.implementation.TOKEN_DECIMAL_SCALER());

        // Get fees
        uint256 marketCreationFee = deployment.factory.MARKET_CREATION_FEE();
        uint256 settlementFees = deployment.factory.SETTLEMENT_FEES();
        uint256 recipientFee = marketCreationFee - settlementFees;

        // Bound initial deposit
        initialDeposit = bound(initialDeposit, maxLoss, _oneTrillionTokens(token));

        // Deal initial deposit + market creation fee to creator
        deal(address(token), MARKET_CREATOR, initialDeposit + marketCreationFee);

        // Approve factory to spend initial deposit + market creation fee
        token.approve(address(deployment.factory), initialDeposit + marketCreationFee);

        // Calculate expectations
        uint256 countBefore = deployment.factory.getTotalMarketProxiesCount();
        uint256 expectedCreatorBalance = token.balanceOf(MARKET_CREATOR) - initialDeposit - marketCreationFee;
        uint256 expectedRecipientBalance = token.balanceOf(MARKET_CREATION_FEE_RECIPIENT) + recipientFee;
        uint256 expectedProxyBalance = initialDeposit + settlementFees;

        // Deploy new market proxy
        address newMarketProxy = deployment.factory
            .deployNewMarketProxy({
                initialDeposit_: initialDeposit,
                newMarketConfig_: marketConfig,
                newMarketMetadata_: _dummyVerifiableUri()
            });

        // Validate proxy registration
        assertTrue(newMarketProxy != address(0), "newMarketProxy is zero address");
        assertTrue(deployment.factory.marketProxyExists(newMarketProxy), "newMarketProxy not registered");
        assertEq(deployment.factory.getTotalMarketProxiesCount(), countBefore + 1, "market proxy count not incremented");

        // Validate proxy initialization
        ILmsrMarket proxy = ILmsrMarket(newMarketProxy);
        assertEq(proxy.marketCreator(), MARKET_CREATOR, "marketCreator mismatch");
        ILmsrMarket.Market memory market = proxy.getMarket();
        assertEq(market.config.outcomeCount, marketConfig.outcomeCount, "outcomeCount mismatch");
        assertEq(market.config.b, marketConfig.b, "b mismatch");
        assertEq(market.config.tradingFee, marketConfig.tradingFee, "tradingFee mismatch");
        assertEq(market.config.tradingDeadline, marketConfig.tradingDeadline, "tradingDeadline mismatch");
        assertEq(market.config.settlementDeadline, marketConfig.settlementDeadline, "settlementDeadline mismatch");
        assertEq(market.pool, initialDeposit, "pool mismatch");

        // Validate token balances
        assertEq(token.balanceOf(MARKET_CREATOR), expectedCreatorBalance, "creator balance mismatch");
        assertEq(
            token.balanceOf(MARKET_CREATION_FEE_RECIPIENT), expectedRecipientBalance, "fee recipient balance mismatch"
        );
        assertEq(token.balanceOf(newMarketProxy), expectedProxyBalance, "proxy balance mismatch");
    }
}
