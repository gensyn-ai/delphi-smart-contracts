// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IEndToEndHandler} from "./IEndToEndHandler.sol";
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

// Contracts
import {LmsrGateway} from "src/lmsr/gateway/LmsrGateway.sol";
import {LmsrMarket} from "src/lmsr/implementation/LmsrMarket.sol";
import {ILmsrMarketTypes} from "src/lmsr/implementation/ILmsrMarketTypes.sol";
import {DelphiFactory} from "src/factory/DelphiFactory.sol";
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Log
import {console2} from "forge-std/console2.sol";

contract EndToEndHandler is IEndToEndHandler, DelphiTestUtils {
    // Invariant Test Config
    uint256 immutable MIN_TRADES_PER_MARKET;
    uint256 immutable MAX_TRADES_PER_MARKET;
    uint256 immutable MAX_TRADER_COUNT;

    // Delphi config
    uint8 public override tokenDecimals;
    uint256 internal _tokenDecimalScaler;
    uint256 internal _minSharesDelta;
    LmsrMarket.MarketConfig internal _marketProxyConfig;

    // Contracts
    IERC20Metadata public override token;
    LmsrGateway public override gateway;
    LmsrMarket public override implementation;
    DelphiFactory public override delphiFactory;
    ILmsrMarket public override marketProxy;
    MockOracleRelayer public override mockOracleRelayer;

    // Market Info
    uint256 public override tradeCount;
    uint256 winningOutcomeIdx;

    mapping(uint256 outcomeIdx => EnumerableSet.AddressSet usersWithShares) internal _outcomeToUsersWithShares;
    mapping(address user => EnumerableSet.UintSet outcomesWithShares) internal _userToOutcomesWithShares;

    EnumerableSet.UintSet internal _losingOutcomeIndicesWithExternalShares;
    EnumerableSet.AddressSet internal _usersWithShares;

    // InvariantArgs
    uint256 invariantSeed;

    uint256 tokenRewardPerShare;

    // Possible Actions
    Action[] possibleActions;

    // Return Counts
    mapping(bytes4 => uint256) public override returnCount;

    // Libraries
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeCast for uint256;
    using Math for uint256;
    using LmsrMath for uint256;

    // ===== CONSTRUCTOR =====
    constructor(uint256 minTradesPerMarket, uint256 maxTradesPerMarket, uint256 maxTraderCount) {
        // Validate test config
        require(minTradesPerMarket <= maxTradesPerMarket, "minTradesPerMARKET should be less than maxTradesPerMARKET");

        // Set invariant test config
        MIN_TRADES_PER_MARKET = minTradesPerMarket;
        MAX_TRADES_PER_MARKET = maxTradesPerMarket;
        MAX_TRADER_COUNT = maxTraderCount;
    }

    // ===== EXTERNAL FUNCTIONS =====
    function step(StepArgs calldata args) external {
        // Reset possible actions
        delete possibleActions;

        invariantSeed = args.invariantArgs.invariantSeed;

        // If not deployed
        if (!deployed()) {
            // DEPLOY_FACTORY_AND_MARKET is possible
            possibleActions.push(Action.DEPLOY_FACTORY_AND_MARKET);

            // If deployed
        } else {
            // Get market status
            ILmsrMarketTypes.MarketStatus marketStatus = marketProxy.marketStatus();

            // If market is OPEN
            if (marketStatus == ILmsrMarketTypes.MarketStatus.OPEN) {
                // If below max trade count
                if (tradeCount < MAX_TRADES_PER_MARKET) {
                    // BUY_EXACT_OUT is possible
                    possibleActions.push(Action.BUY_EXACT_OUT);

                    // If there are losing outcomes with external shares, or the winning outcome has external shares
                    if (_losingOutcomeIndicesWithExternalShares.length() > 0 || externalSupply(winningOutcomeIdx) > 0) {
                        // SELL_EXACT_IN is possible
                        possibleActions.push(Action.SELL_EXACT_IN);
                    }
                }

                // If min trades reached
                if (tradeCount >= MIN_TRADES_PER_MARKET) {
                    // SKIP_TIME is possible
                    possibleActions.push(Action.SKIP_TIME);
                }

                // If market is AWAITING_SETTLEMENT
            } else if (marketStatus == ILmsrMarketTypes.MarketStatus.AWAITING_SETTLEMENT) {
                // Get settlement locked status
                bool settlementLocked = gateway.settlementLocked(address(marketProxy));

                // If settlement is not locked
                if (!settlementLocked) {
                    // RESOLVE_MARKET is possible
                    possibleActions.push(Action.RESOLVE_MARKET);

                    // If settlement is locked
                } else {
                    // SETTLE_MARKET is possible
                    possibleActions.push(Action.SETTLE_MARKET);

                    // FAIL_MARKET is possible
                    possibleActions.push(Action.FAIL_MARKET);
                }

                // If market is SETTLED
            } else if (marketStatus == ILmsrMarketTypes.MarketStatus.SETTLED) {
                // If there are at least _tokenDecimalScaler shares of the winning outcome which haven't been redeemed yet
                if (externalSupply(winningOutcomeIdx) > _tokenDecimalScaler) {
                    // REDEEM is possible
                    possibleActions.push(Action.REDEEM);
                }

                // If market is EXPIRED or FAILED
            } else if (
                marketStatus == ILmsrMarketTypes.MarketStatus.EXPIRED
                    || marketStatus == ILmsrMarketTypes.MarketStatus.FAILED
            ) {
                // If not liquidated yet
                if (_usersWithShares.length() > 0) {
                    // LIQUIDATE is possible
                    possibleActions.push(Action.LIQUIDATE);
                }

                // TRY_SWEEP is possible
                possibleActions.push(Action.TRY_SWEEP);

                // Else
            } else {
                revert("Invalid market status");
            }
        }

        // If no possible actions, return
        if (possibleActions.length == 0) {
            _saveReturn(NoPossibleActions.selector);
            return;
        }

        // Pick random action
        Action action = possibleActions[_getRandomIdx(possibleActions.length, args.actionIdx)];

        console2.log("Step start");
        if (action == Action.DEPLOY_FACTORY_AND_MARKET) {
            console2.log("Deploying factory and market");
            _deployAll(args.deployAll);
        } else if (action == Action.BUY_EXACT_OUT) {
            console2.log("Buying exact out");
            _buyExactOut(args.buyExactOut);
        } else if (action == Action.SELL_EXACT_IN) {
            console2.log("Selling exact in");
            _sellExactIn(args.sellExactIn);
        } else if (action == Action.SKIP_TIME) {
            console2.log("Skipping time");
            _skipTime(args.skipTime);
        } else if (action == Action.RESOLVE_MARKET) {
            console2.log("Resolving market");
            _resolveMarket();
        } else if (action == Action.SETTLE_MARKET) {
            console2.log("Settling market");
            _settleMarket();
        } else if (action == Action.FAIL_MARKET) {
            console2.log("Failing market");
            _failMarket();
        } else if (action == Action.REDEEM) {
            console2.log("Redeeming");
            _redeem(args.redeem);
        } else if (action == Action.LIQUIDATE) {
            console2.log("Liquidating");
            _liquidate(args.liquidate);
        } else if (action == Action.TRY_SWEEP) {
            console2.log("Trying sweep");
            _trySweep();
        } else {
            revert("Invalid action");
        }
        console2.log("Step end");
    }

    function consumeInvariantSeed() external returns (uint256) {
        // Advance the seed by hashing it, so consecutive calls yield a deterministic high entropy series
        invariantSeed = uint256(keccak256(abi.encode(invariantSeed)));

        // Return the new seed
        return invariantSeed;
    }

    // ===== EXTERNAL VIEWS =====
    function tokenDecimalScaler() external view returns (uint256) {
        if (!deployed()) {
            revert("tokenDecimalScaler not set until after token deployment");
        }
        return _tokenDecimalScaler;
    }

    function minSharesDelta() external view returns (uint256) {
        if (!deployed()) {
            revert("minSharesDelta not set until after factory deployment");
        }
        return _minSharesDelta;
    }

    function deployed() public view returns (bool) {
        return address(delphiFactory) != address(0);
    }

    function usersWithShares() external view returns (address[] memory) {
        return _usersWithShares.values();
    }

    function marketProxyConfig() external view returns (LmsrMarket.MarketConfig memory) {
        if (!deployed()) {
            revert("_marketProxyConfig not set until after market deployment");
        }
        return _marketProxyConfig;
    }

    function outcomesWithUserShares(address user) external view returns (uint256[] memory) {
        return _userToOutcomesWithShares[user].values();
    }

    function usersWithOutcomeShares(uint256 outcomeIdx) external view returns (address[] memory) {
        return _outcomeToUsersWithShares[outcomeIdx].values();
    }

    // ========== PUBLIC VIEWS ==========
    function externalSupply(uint256 outcomeIdx) public view returns (uint256) {
        return marketProxy.totalSupply(outcomeIdx) - marketProxy.balanceOf(address(marketProxy), outcomeIdx);
    }

    // ===== INTERNAL =====

    function _deployAll(DeployAllArgs calldata args) internal virtual {
        (MockToken token_, DelphiAddresses memory deployment_,, ILmsrMarket marketProxy_) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: args.tokenDecimals,
            delphiConfig: args.delphiConfig,
            marketConfig: args.marketConfig,
            initialDeposit: args.initialDeposit
        });

        // Set contracts
        token = token_;
        gateway = deployment_.gateway;
        implementation = deployment_.implementation;
        delphiFactory = deployment_.factory;
        marketProxy = marketProxy_;

        // Deploy mock oracle relayer
        mockOracleRelayer = new MockOracleRelayer(gateway);

        // Switch to GATEWAY_OWNER
        _useNewSender(GATEWAY_OWNER);

        // Register oracle relayer on the gateway
        gateway.setOracleRelayer(address(mockOracleRelayer));

        // Set oracle fee recipient
        mockOracleRelayer.setOracleFeeRecipient(address(this));

        /* Set lock only to true on the Mock Oracle Relayer
         * This stops it from immediately settling the market when resolveMarket is called.
         * This is required to reach the FAILED market status.
         */
        mockOracleRelayer.setLockOnly(true);

        // Set remaining vars
        _minSharesDelta = gateway.MIN_SHARES_DELTA();

        // Get market
        ILmsrMarketTypes.Market memory market = marketProxy.getMarket();

        // Set market proxy config
        _marketProxyConfig = market.config;

        // Ensure market is OPEN after deployment
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(ILmsrMarketTypes.MarketStatus.OPEN),
            "_createMarket: marketProxy not OPEN after deployment"
        );

        // Calculate max loss
        uint256 maxLoss = market.config.b.maxLoss(market.config.outcomeCount, implementation.TOKEN_DECIMAL_SCALER());

        // Validate pool and trading fees
        assertGe(market.pool, maxLoss, "_createMarket: pool not greater than or equal to max loss");
        assertEq(market.tradingFees, 0, "_createMarket: trading fees not zero");

        // Pick winning outcome idx
        // Note: We pick this early, so we can make trades converge to the winning outcome over time (if we want).
        winningOutcomeIdx = _getRandomIdx(_marketProxyConfig.outcomeCount, args.winningOutcomeIdx);

        // Set vars
        tokenDecimals = token.decimals();
        _tokenDecimalScaler = 10 ** (18 - tokenDecimals);
    }

    function _buyExactOut(BuyExactOutArgs calldata args) internal {
        // Get random outcome for buy exact out
        uint256 outcomeIdx = _getOutcomeForBuyExactOut(args.outcomeIdx);

        // Get max shares out
        uint256 maxSharesOut = _maxSharesOut(outcomeIdx);

        // Ensure max shares out >= min shares delta
        if (maxSharesOut < _minSharesDelta) {
            vm.assume(false);
        }

        // Pick random shares out
        uint256 sharesOut = bound(args.sharesOut, _minSharesDelta, maxSharesOut);

        // Bound buyer
        // Note: This avoids address(0), without the need for a vm.assume (which reduces coverage)
        uint256 buyerPk = _randomPk(args.buyerPkSeed, 1, MAX_TRADER_COUNT);
        address buyer = vm.addr(buyerPk);

        BuyType buyType = BuyType(_boundUint8(args.buyTypeSeed, 0, uint8(type(BuyType).max)));

        bool success;
        bytes4 errSelector;
        if (buyType == BuyType.BUY_WITH_APPROVAL) {
            (success, errSelector,) = _buy({
                buyer: buyer,
                marketGateway: gateway,
                marketProxy: marketProxy,
                outcomeIdx: outcomeIdx,
                sharesOut: sharesOut,
                maxTokensIn: args.maxTokensIn
            });
        } else {
            (success, errSelector,) = _buyWithPermit({
                buyerPk: buyerPk,
                marketGateway: gateway,
                marketProxy: marketProxy,
                outcomeIdx: outcomeIdx,
                sharesOut: sharesOut,
                maxTokensIn: args.maxTokensIn
            });
        }

        if (!success) {
            _saveReturn(errSelector);
            return;
        }

        // Increment market trade count
        tradeCount++;

        // If outcome is not the winning outcome
        if (outcomeIdx != winningOutcomeIdx) {
            // Add outcome to losing outcomes that can be sold
            _losingOutcomeIndicesWithExternalShares.add(outcomeIdx);
        }

        // Add buyer to users with shares for the outcome
        _outcomeToUsersWithShares[outcomeIdx].add(buyer);

        // Add buyer to users with shares
        _usersWithShares.add(buyer);

        // Add outcome to outcomes with shares for buyer
        _userToOutcomesWithShares[buyer].add(outcomeIdx);
    }

    function _sellExactIn(SellExactInArgs calldata args) internal {
        // Get random outcome for sell exact in
        uint256 outcomeIdx = _getOutcomeForSellExactIn(args.outcomeIdx);

        // Get random user with shares for the outcome
        address seller = _getRandom(_outcomeToUsersWithShares[outcomeIdx].values(), args.sellerIdx);

        // Get seller shares
        uint256 sellerShares = marketProxy.balanceOf(seller, outcomeIdx);

        // Pick random shares in
        uint256 sharesIn = bound(args.sharesIn, _minSharesDelta, sellerShares);

        // Calculate seller shares after sell
        uint256 sellerSharesAfterSell = sellerShares - sharesIn;

        // Ensure seller shares after sell are either 0 or >= minSharesDelta
        if (0 < sellerSharesAfterSell && sellerSharesAfterSell < _minSharesDelta) {
            sharesIn = sellerShares;
            sellerSharesAfterSell = 0;
        }

        // Sell
        (bool success, bytes4 errSelector,) = _sell({
            seller: seller,
            marketGateway: gateway,
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesIn: sharesIn,
            minTokensOut: args.minTokensOut
        });

        if (!success) {
            _saveReturn(errSelector);
            return;
        }

        // Increment market trade count
        tradeCount++;

        // If seller has no shares after sell
        if (sellerSharesAfterSell == 0) {
            // Remove seller from users with shares for the outcome
            _outcomeToUsersWithShares[outcomeIdx].remove(seller);

            // If outcome has no more users with shares
            if (_outcomeToUsersWithShares[outcomeIdx].length() == 0) {
                // Remove outcome from losing outcomes that can be sold
                _losingOutcomeIndicesWithExternalShares.remove(outcomeIdx);
            }

            // Remove seller from users with shares
            _userToOutcomesWithShares[seller].remove(outcomeIdx);

            // If outcome has no more users with shares
            if (_userToOutcomesWithShares[seller].length() == 0) {
                // Remove outcome from outcomes that can be sold
                _usersWithShares.remove(seller);
            }
        }
    }

    function _skipTime(SkipTimeArgs calldata args) internal {
        // Pick random skip action (SKIP_TO_SETTLE or SKIP_TO_EXPIRE)
        SkipTimeAction action = SkipTimeAction(_boundUint8(args.action, 0, uint8(type(SkipTimeAction).max)));

        // Initialize destination timestamp
        uint256 destinationTimestamp;

        // If skipping to settle
        if (action == SkipTimeAction.SKIP_TO_SETTLE) {
            destinationTimestamp = bound(
                args.destinationTimestamp, _marketProxyConfig.tradingDeadline + 1, _marketProxyConfig.settlementDeadline
            );

            // If skipping to expire
        } else if (action == SkipTimeAction.SKIP_TO_EXPIRE) {
            destinationTimestamp =
                bound(args.destinationTimestamp, _marketProxyConfig.settlementDeadline + 1, type(uint256).max);

            // Else
        } else {
            revert("Invalid action");
        }

        // Warp to destination timestamp
        vm.warp(destinationTimestamp);
    }

    function _resolveMarket() internal {
        uint256 tokenPool = marketProxy.getMarket().pool;
        console2.log("winning outcome supply", marketProxy.totalSupply(winningOutcomeIdx));
        if (marketProxy.totalSupply(winningOutcomeIdx) == 0) {
            tokenRewardPerShare = 0;
        } else {
            tokenRewardPerShare = tokenPool.mulDiv(1e18, marketProxy.totalSupply(winningOutcomeIdx));
        }
        console2.log("token reward per share", tokenRewardPerShare);

        // Set outcome on mock oracle, then trigger resolution (resolveMarket → oracle callback → settleMarket)
        mockOracleRelayer.setOutcome(address(marketProxy), winningOutcomeIdx);

        if (block.timestamp < marketProxy.getMarket().config.earliestResolveTime) {
            vm.warp(marketProxy.getMarket().config.earliestResolveTime);
        }
        gateway.resolveMarket(address(marketProxy));
    }

    function _settleMarket() internal {
        // Switch to oracle relayer
        _useNewSender(address(mockOracleRelayer));

        // Settle market
        gateway.settleMarket({
            marketProxy: address(marketProxy), winningOutcomeIdx: winningOutcomeIdx, oracleFeeRecipient: address(this)
        });
    }

    function _failMarket() internal {
        // Switch to oracle relayer
        _useNewSender(address(mockOracleRelayer));

        // Fail market
        gateway.failMarket({marketProxy: address(marketProxy)});
    }

    function _redeem(RedeemArgs calldata args) internal {
        // Get users with winning outcome shares
        address[] memory usersWithWinningOutcomeShares = _outcomeToUsersWithShares[winningOutcomeIdx].values();

        // Get random redeemer
        address redeemer = _getRandom(usersWithWinningOutcomeShares, args.redeemerIdx);

        // If redeemer winning outcome shares are less than token decimal scaler
        if (marketProxy.balanceOf(redeemer, winningOutcomeIdx) < _tokenDecimalScaler) {
            // Continue
            vm.assume(false);
        }

        // Switch to redeemer
        _useNewSender(redeemer);

        // Redeem
        gateway.redeem({marketProxy: marketProxy});

        /* Redemption pulls all winning outcome shares from the redeemer.
         * Therefore, the redeemer will no longer have winning outcome shares.
         */
        _outcomeToUsersWithShares[winningOutcomeIdx].remove(redeemer);
        _userToOutcomesWithShares[redeemer].remove(winningOutcomeIdx);

        // If redeemer has no more outcomes with shares
        if (_userToOutcomesWithShares[redeemer].length() == 0) {
            _usersWithShares.remove(redeemer);
        }
    }

    function _liquidate(LiquidateArgs calldata args) internal {
        // Get liquidator (a random user with shares)
        address liquidator = _getRandom(_usersWithShares.values(), args.liquidatorIdx);

        // Get liquidator's outcomes with shares
        uint256[] memory liquidatorOutcomesWithShares = _userToOutcomesWithShares[liquidator].values();

        // Build outcome indices array
        uint256[] memory outcomeIndices;

        // For each outcome with liquidator shares
        for (uint256 i = 0; i < liquidatorOutcomesWithShares.length; i++) {
            // Get outcome index
            uint256 outcomeIdx = liquidatorOutcomesWithShares[i];

            // Get liquidator shares for the outcome
            uint256 liquidatorShares = marketProxy.balanceOf(liquidator, outcomeIdx);

            // Figure out if outcome is picked
            bool picked = outcomeIdx < args.pickedOutcomesByIdx.length && args.pickedOutcomesByIdx[outcomeIdx];

            // If outcome not picked OR liquidator shares < token decimal scaler
            if (!picked || liquidatorShares < _tokenDecimalScaler) {
                // Continue
                continue;

                // If outcome picked AND liquidator shares >= token decimal scaler
            } else {
                // Add outcome to outcome indices array
                outcomeIndices = _appendToArray(outcomeIndices, outcomeIdx);
            }
        }

        if (outcomeIndices.length == 0) {
            vm.assume(false);
        }

        // Switch to liquidator
        _useNewSender(liquidator);

        // Liquidate
        try gateway.liquidate({marketProxy: marketProxy, outcomeIndices: outcomeIndices}) {
            // For each outcome in outcomeIndices
            for (uint256 i = 0; i < outcomeIndices.length; i++) {
                // Get outcome index
                uint256 outcomeIdx = outcomeIndices[i];

                // Remove liquidator from users with shares for the outcome
                _outcomeToUsersWithShares[outcomeIdx].remove(liquidator);

                // Remove outcome from liquidator's outcomes with shares
                _userToOutcomesWithShares[liquidator].remove(outcomeIdx);

                // If liquidator has no more outcomes with shares
                if (_userToOutcomesWithShares[liquidator].length() == 0) {
                    // Remove liquidator from users with shares
                    _usersWithShares.remove(liquidator);
                }
            }

            // If liquidation fails
        } catch (bytes memory err) {
            _handleCatch(err, _liquidateAllowedErrors());
        }
    }

    function _trySweep() internal {
        // Try sweep
        gateway.trySweep({marketProxy: marketProxy});
    }

    function _saveReturn(bytes4 selector) internal {
        returnCount[selector]++;
    }

    // ========== INTERNAL VIEWS ==========

    function _getOutcomeForBuyExactOut(uint256 outcomeIdxSeed) internal view virtual returns (uint256 outcomeIdx) {
        return _getRandomIdx(_marketProxyConfig.outcomeCount, outcomeIdxSeed);
    }

    function _getOutcomeForSellExactIn(uint256 outcomeIdxSeed) internal view virtual returns (uint256 outcomeIdx) {
        // Get vars
        uint256 losingOutcomesIndicesWithExternalSharesCount = _losingOutcomeIndicesWithExternalShares.length();
        uint256 winningOutcomeExternalSupply = externalSupply(winningOutcomeIdx);

        // If external shares exist for both losing and winning outcomes
        if (losingOutcomesIndicesWithExternalSharesCount > 0 && winningOutcomeExternalSupply > 0) {
            // Build array of all outcomes with external shares (winning or losing)
            uint256[] memory allOutcomeIndicesWithPositiveSupply =
                _appendToArray({arr: _losingOutcomeIndicesWithExternalShares.values(), element: winningOutcomeIdx});

            // Return random outcome (from all outcomes with positive supply)
            outcomeIdx = _getRandom(allOutcomeIndicesWithPositiveSupply, outcomeIdxSeed);

            // If there are only external shares for losing outcomes
        } else if (losingOutcomesIndicesWithExternalSharesCount > 0) {
            // Return random losing outcome
            outcomeIdx = _getRandom(_losingOutcomeIndicesWithExternalShares.values(), outcomeIdxSeed);

            // If there are only external shares for the winning outcome
        } else if (winningOutcomeExternalSupply > 0) {
            // Return the winning outcome
            outcomeIdx = winningOutcomeIdx;

            // If there are no external shares for either
        } else {
            revert("_getOutcomeForSellExactIn: no shares for winning or losing outcomes");
        }

        // Ensure there are users with shares for the selected outcome
        assertGt(
            _outcomeToUsersWithShares[outcomeIdx].length(),
            0,
            "_getOutcomeForSellExactIn: no users with shares for the selected outcome"
        );
    }

    // ========== INTERNAL PURE ==========

    function _appendToArray(uint256[] memory arr, uint256 element) internal pure returns (uint256[] memory newArr) {
        newArr = new uint256[](arr.length + 1);
        for (uint256 i = 0; i < arr.length; i++) {
            newArr[i] = arr[i];
        }
        newArr[arr.length] = element;
    }

    function _maxSharesOut(uint256 outcomeIdx) internal view returns (uint256) {
        // Get outcome current supply
        uint256 outcomeCurrentSupply = marketProxy.totalSupply(outcomeIdx);

        /* outcomeCurrentSupply + sharesOut <= type(uint256).max
         * sharesOut <= type(uint256).max - outcomeCurrentSupply
         */
        uint256 maxSharesOut1 = type(uint256).max - outcomeCurrentSupply;

        /* outcomeNewSupply.mulDiv(1e18, b) <= MAX_EXP_INPUT
         * outcomeNewSupply <= MAX_EXP_INPUT.mulDiv(b, 1e18)
         * outcomeCurrentSupply + sharesOut <= MAX_EXP_INPUT.mulDiv(b, 1e18)
         * sharesOut <= MAX_EXP_INPUT.mulDiv(b, 1e18) - outcomeCurrentSupply
         */
        uint256 maxSharesOut2 = LmsrMath.MAX_EXP_INPUT.mulDiv(_marketProxyConfig.b, 1e18) - outcomeCurrentSupply;

        // Return smallest max
        return Math.min(maxSharesOut1, maxSharesOut2);
    }
}
