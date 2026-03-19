// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Contracts
import {DynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/DynamicParimutuelGateway.sol";
import {DynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/DynamicParimutuelMarket.sol";
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";

// Interfaces
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IEndToEndHandler {
    // Errors
    error NoPossibleActions();

    // Types
    enum Action {
        DEPLOY_FACTORY_AND_MARKET,
        BUY_EXACT_OUT,
        SELL_EXACT_IN,
        SKIP_TIME,
        SUBMIT_WINNER,
        REDEEM,
        LIQUIDATE
    }

    struct StepArgs {
        uint256 actionIdx;
        DeployFactoryAndMarketArgs deployFactoryAndMarket;
        BuyExactOutArgs buyExactOut;
        SellExactInArgs sellExactIn;
        SkipTimeArgs skipTime;
        LiquidateArgs liquidate;
    }

    struct DeployFactoryAndMarketArgs {
        DeployFactoryArgs factory;
        DeployMarketArgs market;
    }

    struct DeployFactoryArgs {
        uint8 decimals;
        uint256 marketCreationFee;
        uint256 tradingFeesRecipientPct;
    }

    struct DeployMarketArgs {
        IDelphiMarket.VerifiableUri newMarketMetadata;
        address marketCreator;
        IDynamicParimutuelMarket.MarketConfig newMarketConfig;
        uint256 initialLiquidity;
        uint256 winningOutcomeIdx;
    }

    struct BuyExactOutArgs {
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

    enum SkipTimeAction {
        SKIP_TO_SETTLE,
        SKIP_TO_EXPIRE
    }

    struct SkipTimeArgs {
        uint256 destinationTimestamp;
        uint8 action;
    }

    struct LiquidateArgs {
        uint256 liquidatorCount;
    }

    // Functions
    function step(StepArgs calldata args) external;

    // Views
    function deployed() external view returns (bool);
    function token() external view returns (IERC20Metadata);
    function returnCount(bytes4 errorSelector) external view returns (uint256);
    function marketProxy() external view returns (IDynamicParimutuelMarket);
    function dynamicParimutuelGateway() external view returns (DynamicParimutuelGateway);
    function dynamicParimutuelImplementation() external view returns (DynamicParimutuelMarket);
    function delphiFactory() external view returns (DelphiFactory);
    function tokenDecimalScaler() external view returns (uint256);
    function minSharesDelta() external view returns (uint256);
    function usersWithShares() external view returns (address[] memory);
    function tokenDecimals() external view returns (uint8);
    function marketProxyConfig() external view returns (DynamicParimutuelMarket.MarketConfig memory);

    function userOutcomesWithShares(address user) external view returns (uint256[] memory);
}
