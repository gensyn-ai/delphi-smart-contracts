// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {IEndToEndHandler} from "./IEndToEndHandler.sol";
import {DelphiDeployer} from "script/utils/deployer/DelphiDeployer.sol";
import {DelphiTestUtils} from "test/utils/DelphiTestUtils.t.sol";

// Libraries
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Contracts
import {DynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/DynamicParimutuelGateway.sol";
import {DynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/DynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";
import {MockToken} from "src/mock/MockToken.sol";

// Interfaces
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Log
import {console2} from "forge-std/console2.sol";

contract EndToEndHandler is IEndToEndHandler, DelphiDeployer, DelphiTestUtils {
    // Constants
    // Question: Move to Factory contract?
    uint256 private constant _MIN_MARKET_CREATION_FEE_18 = 0;
    uint256 private constant _MAX_MARKET_CREATION_FEE_18 = 100e18; // 100 tokens
    uint256 private constant _MIN_TRADING_FEES_RECIPIENT_PCT = 0; // 0%
    uint256 private constant _MAX_TRADING_FEES_RECIPIENT_PCT = 1e18; // 100%
    uint256 public constant MAX_SHARES_OUT = 1_000_000e18; // 1 Millon

    // Invariant Test Config
    uint256 immutable MIN_TRADES_PER_MARKET;
    uint256 immutable MAX_TRADES_PER_MARKET;
    uint256 immutable MAX_TRADER_COUNT;
    address immutable TOKEN_ADMIN = makeAddr("TOKEN_ADMIN");
    address immutable TRADING_FEES_RECIPIENT = makeAddr("TRADING_FEES_RECIPIENT");
    address immutable MARKET_CREATION_FEE_RECIPIENT = makeAddr("MARKET_CREATION_FEE_RECIPIENT");

    // Delphi config
    uint8 public override tokenDecimals;
    uint256 internal _tokenDecimalScaler;
    uint256 internal _minMarketCreationFee;
    uint256 internal _maxMarketCreationFee;
    uint256 internal _minSharesDelta;
    uint256 internal _minTokensDelta;
    DynamicParimutuelMarket.MarketConfig internal _marketProxyConfig;

    // Contracts
    IERC20Metadata public override token;
    DynamicParimutuelGateway public override dynamicParimutuelGateway;
    DynamicParimutuelMarket public override dynamicParimutuelImplementation;
    DelphiFactory public override delphiFactory;
    IDynamicParimutuelMarket public override marketProxy;

    // Market Info
    uint256 tradeCount;
    uint256 winningOutcomeIdx;

    EnumerableSet.UintSet internal _losingOutcomeIndicesWithExternalShares;
    mapping(uint256 outcomeIdx => EnumerableSet.AddressSet usersWithShares) internal _outcomeToUsersWithShares;

    EnumerableSet.AddressSet internal _usersWithShares;
    mapping(address user => EnumerableSet.UintSet outcomesWithShares) internal _userToOutcomesWithShares;

    uint256 tokenRewardPerShare;

    bool redeemed;
    bool liquidated;

    // Possible Actions
    Action[] possibleActions;

    // Return Counts
    mapping(bytes4 => uint256) public returnCount;

    // Libraries
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeCast for uint256;
    using Math for uint256;

    constructor(uint256 minTradesPerMarket, uint256 maxTradesPerMarket, uint256 maxTraderCount) {
        // Validate test config
        require(minTradesPerMarket <= maxTradesPerMarket, "minTradesPerMARKET should be less than maxTradesPerMARKET");

        // Set invariant test config
        MIN_TRADES_PER_MARKET = minTradesPerMarket;
        MAX_TRADES_PER_MARKET = maxTradesPerMarket;
        MAX_TRADER_COUNT = maxTraderCount;
    }

    // ===== EXTERNAL ENTRYPOINT =====
    function step(StepArgs calldata args) external {
        // Reset possible actions
        delete possibleActions;

        // If not deployed
        if (!deployed()) {
            // DEPLOY_FACTORY_AND_MARKET is possible
            possibleActions.push(Action.DEPLOY_FACTORY_AND_MARKET);

            // If deployed
        } else {
            // Get market status
            IDynamicParimutuelMarketTypes.MarketStatus marketStatus = marketProxy.marketStatus();

            // If market is OPEN
            if (marketStatus == IDynamicParimutuelMarketTypes.MarketStatus.OPEN) {
                // If below max trade count
                if (tradeCount < MAX_TRADES_PER_MARKET) {
                    // BUY_EXACT_OUT is possible
                    possibleActions.push(Action.BUY_EXACT_OUT);

                    // If there are losing outcomes with external shares, or the winning outcome has external shares
                    if (_losingOutcomeIndicesWithExternalShares.length() > 0 || _externalSupply(winningOutcomeIdx) > 0)
                    {
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
            } else if (marketStatus == IDynamicParimutuelMarketTypes.MarketStatus.AWAITING_SETTLEMENT) {
                // SUBMIT_WINNER is possible
                possibleActions.push(Action.SUBMIT_WINNER);

                // If market is SETTLED
            } else if (marketStatus == IDynamicParimutuelMarketTypes.MarketStatus.SETTLED) {
                // If there are users with shares of the winning outcome, and they haven't redeemed yet
                // Question: If _redeem is redeeming everything, can't the _externalSupply view replace the redeemed bool?
                if (_externalSupply(winningOutcomeIdx) > 0 && !redeemed) {
                    // REDEEM is possible
                    possibleActions.push(Action.REDEEM);
                }

                // If market is EXPIRED
            } else {
                // If not liquidated yet
                // Question: If _liquidate liquidates everything, can't the _externalSupply view replace the liquidated bool?
                if (!liquidated) {
                    // LIQUIDATE is possible
                    possibleActions.push(Action.LIQUIDATE);
                }
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
            _deployFactoryAndMarket(args.deployFactoryAndMarket);
        } else if (action == Action.BUY_EXACT_OUT) {
            console2.log("Buying exact out");
            _buyExactOut(args.buyExactOut);
        } else if (action == Action.SELL_EXACT_IN) {
            console2.log("Selling exact in");
            _sellExactIn(args.sellExactIn);
        } else if (action == Action.SKIP_TIME) {
            console2.log("Skipping time");
            _skipTime(args.skipTime);
        } else if (action == Action.SUBMIT_WINNER) {
            console2.log("Submitting winner");
            _submitWinner();
        } else if (action == Action.REDEEM) {
            console2.log("Redeeming");
            _redeem();
        } else if (action == Action.LIQUIDATE) {
            console2.log("Liquidating");
            _liquidate(args.liquidate);
        } else {
            revert("Invalid action");
        }
        console2.log("Step end");
    }

    function _deployFactoryAndMarket(DeployFactoryAndMarketArgs calldata args) internal {
        _deployFactory(args.factory);
        _deployMarket(args.market);
        _minTokensDelta = dynamicParimutuelGateway.MIN_TOKENS_DELTA();
    }

    function _deployFactory(DeployFactoryArgs calldata args) internal {
        // Deploy Token
        token = new MockToken({_decimals: _boundUint8(args.decimals, 6, 18), admin: TOKEN_ADMIN, initialAmount: 0});

        // Set vars
        tokenDecimals = token.decimals();
        _tokenDecimalScaler = 10 ** (18 - tokenDecimals);
        _minMarketCreationFee = _MIN_MARKET_CREATION_FEE_18 / _tokenDecimalScaler;
        _maxMarketCreationFee = _MAX_MARKET_CREATION_FEE_18 / _tokenDecimalScaler;

        // Deploy Delphi
        DelphiAddresses memory delphiAddresses = _deployDelphi(
            DelphiConfig({
                tradingFeesRecipient: TRADING_FEES_RECIPIENT,
                marketCreationFeeRecipient: MARKET_CREATION_FEE_RECIPIENT,
                marketCreationFee: bound(args.marketCreationFee, _minMarketCreationFee, _maxMarketCreationFee),
                tradingFeesRecipientPct: bound(
                    args.tradingFeesRecipientPct, _MIN_TRADING_FEES_RECIPIENT_PCT, _MAX_TRADING_FEES_RECIPIENT_PCT
                ),
                token: token
            })
        );

        // Set contracts
        dynamicParimutuelGateway = delphiAddresses.dynamicParimutuelGateway;
        dynamicParimutuelImplementation = delphiAddresses.dynamicParimutuelImplementation;
        delphiFactory = delphiAddresses.delphiFactory;

        // Set remaining vars
        _minSharesDelta = dynamicParimutuelGateway.MIN_SHARES_DELTA();
    }

    function _deployMarket(DeployMarketArgs memory args) internal virtual {
        // Generate new market config
        args = _boundDeployMarketArgs({implementation: dynamicParimutuelImplementation, args: args});

        // Get market creator balance
        uint256 marketCreatorBalance = token.balanceOf(args.marketCreator);

        // Calculate market creation cost
        uint256 marketCreationCost = delphiFactory.MARKET_CREATION_FEE() + args.initialLiquidity;

        // If market creator can't afford the market creation cost
        if (marketCreatorBalance < marketCreationCost) {
            // Deal to market creator
            deal(address(token), args.marketCreator, marketCreationCost);
        }

        // Switch to market creator
        _useNewSender(args.marketCreator);

        // Approve delphi factory to pull market creation cost
        token.approve(address(delphiFactory), marketCreationCost);

        // Deploy new market proxy
        marketProxy = IDynamicParimutuelMarket(
            delphiFactory.deployNewMarketProxy({
                initialLiquidity_: args.initialLiquidity,
                newMarketMetadata_: args.newMarketMetadata,
                newMarketInitializationCalldata_: abi.encode(args.newMarketConfig)
            })
        );

        // Set market proxy config
        _marketProxyConfig = marketProxy.getMarket().config;

        // Ensure market is OPEN after deployment
        assertEq(
            uint8(marketProxy.marketStatus()),
            uint8(IDynamicParimutuelMarketTypes.MarketStatus.OPEN),
            "_createMarket: marketProxy not OPEN after deployment"
        );

        // Calculate expected initial price
        uint256 expectedInitialPrice =
            (args.newMarketConfig.b * ONE) / ((args.newMarketConfig.outcomeCount * 1e36).sqrt() * _tokenDecimalScaler);

        // Pick winning outcome idx
        winningOutcomeIdx = _getRandomIdx(args.newMarketConfig.outcomeCount, args.winningOutcomeIdx);

        // For each outcome
        for (uint256 outcomeIdx = 0; outcomeIdx < args.newMarketConfig.outcomeCount; outcomeIdx++) {
            // Ensure outcome's price matches expectations
            assertApproxEqRel(
                marketProxy.spotPrice(outcomeIdx),
                expectedInitialPrice,
                BASIS_POINT,
                "outcomes in newly created market are not equally priced"
            );
        }
    }

    function _buyExactOut(BuyExactOutArgs calldata args) internal {
        // Get random outcome for buy exact out
        uint256 outcomeIdx = _getOutcomeForBuyExactOut(args.outcomeIdx);

        // Pick random shares out
        uint256 sharesOut = bound(args.sharesOut, _minSharesDelta, MAX_SHARES_OUT);

        // Bound buyer
        // Note: This avoids address(0), without the need for a vm.assume (which reduces coverage)
        address buyer = _randomAddressFromPk(args.buyerPkSeed, 1, MAX_TRADER_COUNT);

        // Buy
        (bool success, bytes4 errSelector,) = _buy({
            buyer: buyer,
            marketGateway: dynamicParimutuelGateway,
            marketProxy: marketProxy,
            outcomeIdx: outcomeIdx,
            sharesOut: sharesOut,
            maxTokensIn: args.maxTokensIn
        });

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
        address seller = _randomAddressArrayElement(_outcomeToUsersWithShares[outcomeIdx].values(), args.sellerIdx);

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
            marketGateway: dynamicParimutuelGateway,
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
        SkipTimeAction action = SkipTimeAction(_boundUint8(args.action, 0, 1));

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

    function _submitWinner() internal {
        // Switch to market creator
        _useNewSender(marketProxy.marketCreator());

        uint256 tokenPool = marketProxy.getMarket().pool;
        tokenRewardPerShare = tokenPool.mulDiv(1e18, marketProxy.totalSupply(winningOutcomeIdx));

        // Submit winner (via safe)
        dynamicParimutuelGateway.submitWinner(marketProxy, winningOutcomeIdx);
    }

    function _redeem() internal {
        // For each user with winning shares
        for (uint256 i = 0; i < _outcomeToUsersWithShares[winningOutcomeIdx].length(); i++) {
            // Get user
            address user = _outcomeToUsersWithShares[winningOutcomeIdx].at(i);

            // Get user winning shares
            uint256 userWinningShares = marketProxy.balanceOf(user, winningOutcomeIdx);

            // If user has no winning shares, continue to next user
            if (userWinningShares == 0) {
                continue;
            }

            // Switch to user
            _useNewSender(user);

            // Redeem
            (, uint256 tokensOut) = dynamicParimutuelGateway.redeem(marketProxy);

            // Calculate expected tokens out
            uint256 expectedTokensOut = userWinningShares.mulDiv(tokenRewardPerShare, 1e18);

            // Validate
            assertApproxEqAbsDecimal(
                tokensOut, // left
                expectedTokensOut, // right
                BASIS_POINT, // tolerance
                tokenDecimals, // decimals
                "_redeem: unexpected tokens out"
            );
        }

        // Ensure market has all shares
        assertEqDecimal(
            marketProxy.balanceOf(address(marketProxy), winningOutcomeIdx),
            marketProxy.totalSupply(winningOutcomeIdx),
            tokenDecimals,
            "_redeem: not all winning shares redeemed"
        );
        assertEqDecimal(
            marketProxy.getMarket().pool, // left
            0, // right
            tokenDecimals, // decimals
            "_redeem: market pool not empty after all redemptions"
        );
        assertEqDecimal(
            marketProxy.getMarket().tradingFees,
            0,
            tokenDecimals,
            "_redeem: market trading fees not empty after all redemptions"
        );
        assertApproxEqAbsDecimal(
            token.balanceOf(address(marketProxy)),
            0,
            BASIS_POINT,
            tokenDecimals,
            "_redeem: market token balance not zero after all redemptions"
        );

        // Mark as redeemed
        redeemed = true;
    }

    function _liquidate(LiquidateArgs calldata args) internal {
        // Initialize share bank
        address shareBank = makeAddr("shareBank");

        // Get users with shares count
        uint256 usersWithSharesCount = _usersWithShares.length();

        // If there are no users with shares
        if (usersWithSharesCount == 0) {
            // Cannot Liquidate. Exit
            // _saveReturn(NoUsersWithShares.selector);
            return;
        }

        // For each user
        for (uint256 i = 0; i < usersWithSharesCount; i++) {
            // Get user
            address user = _usersWithShares.at(i);

            // Get user outcomes with shares
            uint256[] memory userOutcomeIndices = _userToOutcomesWithShares[user].values();

            // For each outcome with user shares
            for (uint256 j = 0; j < userOutcomeIndices.length; j++) {
                // Get outcome index
                uint256 outcomeIdx = userOutcomeIndices[j];

                // Get user shares for the outcome
                uint256 userShares = marketProxy.balanceOf(user, outcomeIdx);

                // Switch to user
                _useNewSender(user);

                // Transfer user shares to share bank
                marketProxy.transfer(shareBank, outcomeIdx, userShares);

                // Add outcome to outcomes with shares for share bank
                _userToOutcomesWithShares[shareBank].add(outcomeIdx);
            }
        }

        // Get share bank outcomes with shares
        uint256[] memory shareBankOutcomeIndices = _userToOutcomesWithShares[shareBank].values();

        // Initialize array to track share bank shares for each outcome
        uint256[] memory bankSharesPerOutcome = new uint256[](shareBankOutcomeIndices.length);

        // Initialize shares bank lowest outcome balance
        uint256 shareBankLowestOutcomeBalance = type(uint256).max;

        // For each outcome
        for (uint256 i = 0; i < shareBankOutcomeIndices.length; i++) {
            // Get outcome index
            uint256 outcomeIdx = shareBankOutcomeIndices[i];

            // Get share bank shares for the outcome
            uint256 shareBankOutcomeShares = marketProxy.balanceOf(shareBank, outcomeIdx);

            // Save share bank shares for the outcome
            // Note: use i here, not outcomeIdx
            bankSharesPerOutcome[i] = shareBankOutcomeShares;

            // If new lowest outcome balance
            if (shareBankOutcomeShares < shareBankLowestOutcomeBalance) {
                // Update share bank lowest outcome balance
                shareBankLowestOutcomeBalance = shareBankOutcomeShares;
            }
        }

        // Validate share bank lowest outcome balance
        assertGt(
            shareBankLowestOutcomeBalance, 0, "_liquidate: share bank lowest outcome balance is zero, cannot liquidate"
        );

        // Bound liquidator count
        // Note: cap to 10 to prevent `OutOfGas` errors
        uint256 liquidatorCount = bound(args.liquidatorCount, 1, Math.min(shareBankLowestOutcomeBalance, 10));

        // Initialize var
        uint256 firstLiquidatorTotalTokensOut;

        // For each liquidator
        for (uint256 i = 0; i < liquidatorCount; i++) {
            // Get liquidator
            address liquidator = makeAddr(string(abi.encodePacked("liquidator", vm.toString(i))));

            // For each outcome with shares in share bank
            for (uint256 j = 0; j < shareBankOutcomeIndices.length; j++) {
                // Get outcome index
                uint256 outcomeIdx = shareBankOutcomeIndices[j];

                // Calculate outcome shares per liquidator
                // Note: use j here, not outcomeIdx
                uint256 outcomeSharesPerLiquidator = bankSharesPerOutcome[j] / liquidatorCount;

                // Ensure outcome shares per liquidator is greater than zero
                assertGt(outcomeSharesPerLiquidator, 0, "_liquidate: outcome shares per liquidator is zero");

                // Switch to share bank
                _useNewSender(shareBank);

                // Give shares to liquidator
                marketProxy.transfer(liquidator, outcomeIdx, outcomeSharesPerLiquidator);
            }

            // Switch to liquidator
            _useNewSender(liquidator);

            // Liquidate
            (, uint256 totalTokensOut) =
                dynamicParimutuelGateway.liquidate({marketProxy: marketProxy, outcomeIndices: shareBankOutcomeIndices});

            // If first liquidator
            if (i == 0) {
                // Save total tokens out for first liquidator
                firstLiquidatorTotalTokensOut = totalTokensOut;

                // If not first liquidator
            } else {
                // Ensure liquidations are order-independent
                assertEq(
                    totalTokensOut,
                    firstLiquidatorTotalTokensOut,
                    "_liquidate: total tokens out not equal for liquidators with equal shares"
                );
            }
        }

        // Ensure market is empty after all liquidations
        for (uint256 outcomeIdx = 0; outcomeIdx < _marketProxyConfig.outcomeCount; outcomeIdx++) {
            assertApproxEqAbsDecimal(
                marketProxy.balanceOf(address(marketProxy), outcomeIdx),
                marketProxy.totalSupply(outcomeIdx),
                BASIS_POINT,
                tokenDecimals,
                "_liquidate: not all shares liquidated for outcome index"
            );
        }
        // assertEqDecimal(marketProxy.getMarket().pool, 0, tokenDecimals, "market pool not empty after all liquidations");
        assertApproxEqAbsDecimal(
            marketProxy.getMarket().tradingFees,
            0,
            BASIS_POINT,
            tokenDecimals,
            "_liquidate: market trading fees not empty after all liquidations"
        );
        assertApproxEqAbsDecimal(
            token.balanceOf(address(marketProxy)),
            0,
            BASIS_POINT,
            tokenDecimals,
            "_liquidate: market token balance not zero after all liquidations"
        );

        // Mark as liquidated
        liquidated = true;
    }

    // ========== EXTERNAL VIEWS ==========
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

    function marketProxyConfig() external view returns (DynamicParimutuelMarket.MarketConfig memory) {
        if (!deployed()) {
            revert("_marketProxyConfig not set until after market deployment");
        }
        return _marketProxyConfig;
    }

    // ========== INTERNAL ==========
    function _saveReturn(bytes4 selector) internal {
        returnCount[selector]++;
    }

    function _getOutcomeForBuyExactOut(uint256 outcomeIdxSeed) internal view virtual returns (uint256 outcomeIdx) {
        return _getRandomIdx(_marketProxyConfig.outcomeCount, outcomeIdxSeed);
    }

    function _getOutcomeForSellExactIn(uint256 outcomeIdxSeed) internal view virtual returns (uint256 outcomeIdx) {
        // Get vars
        uint256 losingOutcomesIndicesWithExternalSharesCount = _losingOutcomeIndicesWithExternalShares.length();
        uint256 winningOutcomeExternalSupply = _externalSupply(winningOutcomeIdx);

        // If external shares exist for both losing and winning outcomes
        if (losingOutcomesIndicesWithExternalSharesCount > 0 && winningOutcomeExternalSupply > 0) {
            // Build array of all outcomes with external shares (winning or losing)
            uint256[] memory allOutcomeIndicesWithPositiveSupply =
                _appendToArray({arr: _losingOutcomeIndicesWithExternalShares.values(), element: winningOutcomeIdx});

            // Return random outcome (from all outcomes with positive supply)
            outcomeIdx = _randomUintArrayElement(allOutcomeIndicesWithPositiveSupply, outcomeIdxSeed);

            // If there are only external shares for losing outcomes
        } else if (losingOutcomesIndicesWithExternalSharesCount > 0) {
            // Return random losing outcome
            outcomeIdx = _randomUintArrayElement(_losingOutcomeIndicesWithExternalShares.values(), outcomeIdxSeed);

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

    function _randomAddressArrayElement(address[] memory arr, uint256 idxSeed) internal pure returns (address) {
        return arr[_getRandomIdx(arr.length, idxSeed)];
    }

    function _randomUintArrayElement(uint256[] memory arr, uint256 idxSeed) internal pure returns (uint256) {
        return arr[_getRandomIdx(arr.length, idxSeed)];
    }

    function _getRandomIdx(uint256 length, uint256 seed) internal pure returns (uint256) {
        require(length > 0, "_getRandomIdx: length cannot be zero");
        return bound(seed, 0, length - 1);
    }

    function _externalSupply(uint256 outcomeIdx) internal view returns (uint256) {
        return marketProxy.totalSupply(outcomeIdx) - marketProxy.balanceOf(address(marketProxy), outcomeIdx);
    }

    function _appendToArray(uint256[] memory arr, uint256 element) internal pure returns (uint256[] memory newArr) {
        newArr = new uint256[](arr.length + 1);
        for (uint256 i = 0; i < arr.length; i++) {
            newArr[i] = arr[i];
        }
        newArr[arr.length] = element;
    }

    function userOutcomesWithShares(address user) external view returns (uint256[] memory) {
        return _userToOutcomesWithShares[user].values();
    }
}
