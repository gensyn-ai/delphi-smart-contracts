// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {DelphiFactory} from "src/factory/DelphiFactory.sol";
import {DelphiDeployer} from "script/utils/deployer/DelphiDeployer.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IEndToEndHandler {
    // ===== ERRORS =====
    error NoPossibleActions();

    // ===== ENUMS =====
    enum Action {
        DEPLOY_FACTORY_AND_MARKET,
        BUY_EXACT_OUT,
        SELL_EXACT_IN,
        SKIP_TIME,
        RESOLVE_MARKET,
        SETTLE_MARKET,
        FAIL_MARKET,
        REDEEM,
        LIQUIDATE,
        TRY_SWEEP
    }

    // ===== STRUCTS =====
    struct StepArgs {
        InvariantArgs invariantArgs;
        uint256 actionIdx;
        DeployAllArgs deployAll;
        BuyExactOutArgs buyExactOut;
        SellExactInArgs sellExactIn;
        SkipTimeArgs skipTime;
        RedeemArgs redeem;
        LiquidateArgs liquidate;
    }

    struct InvariantArgs {
        uint256 invariantSeed;
    }

    struct DeployAllArgs {
        uint8 tokenDecimals;
        DelphiDeployer.DelphiConfig delphiConfig;
        ILmsrMarket.MarketConfig marketConfig;
        uint256 initialDeposit;
        uint256 winningOutcomeIdx;
    }

    struct BuyExactOutArgs {
        uint8 buyTypeSeed;
        uint256 buyerPkSeed;
        uint256 outcomeIdx;
        uint256 sharesOut;
        uint256 maxTokensIn;
    }

    struct SellExactInArgs {
        uint256 sellerIdx;
        uint256 outcomeIdx;
        uint256 sharesIn;
        uint256 minTokensOut;
    }

    enum BuyType {
        BUY_WITH_APPROVAL,
        BUY_WITH_PERMIT
    }

    enum SkipTimeAction {
        SKIP_TO_SETTLE,
        SKIP_TO_EXPIRE
    }

    struct SkipTimeArgs {
        uint256 destinationTimestamp;
        uint8 action;
    }

    struct RedeemArgs {
        uint256 redeemerIdx;
    }

    struct LiquidateArgs {
        uint256 liquidatorIdx;
        bool[] pickedOutcomesByIdx;
    }

    // ===== EXTERNAL FUNCTIONS =====
    function step(StepArgs calldata args) external;
    function consumeInvariantSeed() external returns (uint256);

    // ===== EXTERNAL VIEWS =====

    // Delphi Config
    function tokenDecimals() external view returns (uint8);

    // Contracts
    function token() external view returns (IERC20Metadata);
    function gateway() external view returns (LmsrGateway);
    function implementation() external view returns (LmsrMarket);
    function delphiFactory() external view returns (DelphiFactory);
    function marketProxy() external view returns (ILmsrMarket);
    function mockOracleRelayer() external view returns (MockOracleRelayer);

    // Market Info
    function tradeCount() external view returns (uint256);

    // Return Counts
    function returnCount(bytes4 errorSelector) external view returns (uint256);

    // External Views
    function tokenDecimalScaler() external view returns (uint256);
    function minSharesDelta() external view returns (uint256);
    function deployed() external view returns (bool);
    function usersWithShares() external view returns (address[] memory);
    function marketProxyConfig() external view returns (LmsrMarket.MarketConfig memory);
    function outcomesWithUserShares(address user) external view returns (uint256[] memory);
    function usersWithOutcomeShares(uint256 outcomeIdx) external view returns (address[] memory);

    // Public Views
    function externalSupply(uint256 outcomeIdx) external view returns (uint256);
}
