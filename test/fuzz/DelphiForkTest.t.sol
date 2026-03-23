// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiDeployer} from "script/utils/deployer/DelphiDeployer.sol";
import {DelphiTestUtils} from "test/utils/DelphiTestUtils.t.sol";

// Interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDelphiMarket} from "src/delphi/IDelphiMarket.sol";
import {IDynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarket.sol";
import {
    IDynamicParimutuelMarketTypes
} from "src/delphi/dynamicParimutuel/implementation/IDynamicParimutuelMarketTypes.sol";
import {
    IDynamicParimutuelGatewayErrors
} from "src/delphi/dynamicParimutuel/gateway/IDynamicParimutuelGatewayErrors.sol";

// Contracts
import {DynamicParimutuelGateway} from "src/delphi/dynamicParimutuel/gateway/DynamicParimutuelGateway.sol";
import {DynamicParimutuelMarket} from "src/delphi/dynamicParimutuel/implementation/DynamicParimutuelMarket.sol";
import {DelphiFactory} from "src/delphi/factory/DelphiFactory.sol";

interface IUsdc {
    function owner() external view returns (address);
    function updateMasterMinter(address _newMasterMinter) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function mint(address to, uint256 amount) external;
}

contract DelphiFork_Test is DelphiDeployer, DelphiTestUtils {
    // Immutables
    address immutable ADMIN = makeAddr("ADMIN");
    address immutable USER = makeAddr("USER");

    // Contracts
    DynamicParimutuelGateway gateway;
    DynamicParimutuelMarket implementation;
    DelphiFactory factory;

    // Other
    // forge-lint: disable-next-line(unsafe-cheatcode)
    string networksConfigToml = vm.readFile("config/networks.toml");

    // Structs
    struct Args {
        uint256 marketCreationFee;
        uint256 tradingFeesRecipient;
        uint256 initialLiquidity;
        uint256 outcomeCount;
        uint256 k;
        uint256 tradingFee;
        uint256 tradingWindow;
        uint256 settlementWindow;
        uint256 outcomeIdx;
        uint256 sharesDelta;
        bool redeem;
    }

    // Tests

    /// forge-config: default.fuzz.runs = 256
    function test_Fork_GensynTestnet(Args calldata args) external {
        _test({networkAlias: "gensyn-testnet", args: args});
    }

    /// forge-config: default.fuzz.runs = 256
    function test_Fork_GensynMainnet(Args calldata args) external {
        _test({networkAlias: "gensyn-mainnet", args: args});
    }

    // Internal Utils
    function _test(string memory networkAlias, Args calldata args) internal {
        // Get block number
        uint256 blockNumber =
            abi.decode(vm.parseToml(networksConfigToml, string.concat(".", networkAlias, ".block")), (uint256));

        // Fork (from block number)
        vm.createSelectFork(networkAlias, blockNumber);

        // Get usdc
        IERC20Metadata usdc = IERC20Metadata(
            abi.decode(vm.parseToml(networksConfigToml, string.concat(".", networkAlias, ".usdc")), (address))
        );

        // Configure minter
        _configureMinter(IUsdc(address(usdc)));

        // Deploy Delphi
        uint256 marketCreationFee = _deployDelphi(usdc, args);

        // Deploy Market
        (uint256 outcomeCount, address newMarketProxy, uint256 tradingDeadline, uint256 settlementDeadline) =
            _deployMarket(usdc, args, marketCreationFee);

        // Pick shares delta
        uint256 sharesDelta = bound(args.sharesDelta, gateway.MIN_SHARES_DELTA(), 1_000_000_000_000e6);

        // Pick outcome idx
        uint256 outcomeIdx = bound(args.outcomeIdx, 0, outcomeCount - 1);

        // Get quote
        try gateway.quoteBuyExactOut({
            marketProxy: IDynamicParimutuelMarket(newMarketProxy), outcomeIdx: outcomeIdx, sharesOut: sharesDelta
        }) returns (
            uint256 tokensIn
        ) {
            // Deal tokensIn to USER
            _deal({token: usdc, recipient: USER, desiredBalance: tokensIn});

            // Switch to USER
            _useNewSender(USER);

            // Approve market to pull USER tokens
            usdc.approve(newMarketProxy, tokensIn);

            // User buys
            gateway.buyExactOut({
                marketProxy: IDynamicParimutuelMarket(newMarketProxy),
                outcomeIdx: outcomeIdx,
                sharesOut: sharesDelta,
                maxTokensIn: type(uint256).max
            });

            // User sells
            try gateway.sellExactIn({
                marketProxy: IDynamicParimutuelMarket(newMarketProxy),
                outcomeIdx: outcomeIdx,
                sharesIn: sharesDelta,
                minTokensOut: 0
            }) {
                // Deal tokensIn to USER
                _deal({token: usdc, recipient: USER, desiredBalance: tokensIn});

                // Switch to USER
                _useNewSender(USER);

                // Approve market to pull USER tokens
                usdc.approve(newMarketProxy, tokensIn);

                // User buys again (to have shares to redeem or liquidate later)
                gateway.buyExactOut({
                    marketProxy: IDynamicParimutuelMarket(newMarketProxy),
                    outcomeIdx: outcomeIdx,
                    sharesOut: sharesDelta,
                    maxTokensIn: type(uint256).max
                });

                // If redeem
                if (args.redeem) {
                    // Warp past trading deadline
                    vm.warp(tradingDeadline + 1);

                    // Submit Winner
                    gateway.submitWinner({
                        marketProxy: IDynamicParimutuelMarket(newMarketProxy), winningOutcomeIdx: outcomeIdx
                    });

                    // Redeem
                    gateway.redeem({marketProxy: IDynamicParimutuelMarket(newMarketProxy)});

                    // If not redeem
                } else {
                    // Warp past settlement deadline
                    vm.warp(settlementDeadline + 1);

                    // Build outcome indices
                    uint256[] memory outcomeIndices = new uint256[](1);
                    outcomeIndices[0] = outcomeIdx;

                    // Liquidate
                    gateway.liquidate({
                        marketProxy: IDynamicParimutuelMarket(newMarketProxy), outcomeIndices: outcomeIndices
                    });
                }

                // Do nothing for now
            } catch (bytes memory err) {
                _handleCatch(err, IDynamicParimutuelGatewayErrors.TokensOutBelowMin.selector);
            }
        } catch (bytes memory err) {
            _handleCatch(err, IDynamicParimutuelGatewayErrors.TokensInBelowMin.selector);
        }
    }

    function _configureMinter(IUsdc token) internal {
        // Switch to token owner
        _useNewSender(token.owner());

        // Update master minter to this contract
        token.updateMasterMinter(address(this));

        // Switch to new master minter (this contract)
        _useNewSender(address(this));

        // Configure ADMIN as minter, with unlimited minting allowance
        token.configureMinter(ADMIN, type(uint256).max);
    }

    function _deployDelphi(IERC20Metadata token, Args calldata args) internal returns (uint256 marketCreationFee) {
        // Pick market creation fee
        marketCreationFee = bound(args.marketCreationFee, 0, 100e6);

        // Deploy Delphi
        DelphiAddresses memory delphiAddresses = _deployDelphi({
            args: DelphiConfig({
                tradingFeesRecipient: ADMIN,
                marketCreationFeeRecipient: ADMIN,
                marketCreationFee: marketCreationFee,
                tradingFeesRecipientPct: bound(args.tradingFeesRecipient, 0, 1e18),
                token: token
            })
        });

        // Set state variables for easier access
        gateway = delphiAddresses.dynamicParimutuelGateway;
        implementation = delphiAddresses.dynamicParimutuelImplementation;
        factory = delphiAddresses.delphiFactory;
    }

    function _deployMarket(IERC20Metadata token, Args calldata args, uint256 marketCreationFee)
        internal
        returns (uint256 outcomeCount, address newMarketProxy, uint256 tradingDeadline, uint256 settlementDeadline)
    {
        // Pick initial liquidity
        uint256 initialLiquidity = bound(
            args.initialLiquidity, implementation.MIN_INITIAL_LIQUIDITY(), implementation.MAX_INITIAL_LIQUIDITY()
        );

        // Switch to ADMIN
        _useNewSender(ADMIN);

        // Deal tokens to USER
        _deal({token: token, recipient: USER, desiredBalance: initialLiquidity + marketCreationFee});

        // Switch to USER
        _useNewSender(USER);

        // USER gives approves factory to spend their tokens for market creation
        token.approve(address(factory), marketCreationFee + initialLiquidity);

        // Get outcome count
        outcomeCount = bound(args.outcomeCount, implementation.MIN_OUTCOME_COUNT(), implementation.MAX_OUTCOME_COUNT());

        // Pick trading deadline
        uint256 tradingWindow =
            bound(args.tradingWindow, implementation.MIN_TRADING_WINDOW(), implementation.MAX_TRADING_WINDOW());
        tradingDeadline = block.timestamp + tradingWindow;

        // Pick settlement deadline
        uint256 settlementWindow = bound(
            args.settlementWindow, implementation.MIN_SETTLEMENT_WINDOW(), implementation.MAX_SETTLEMENT_WINDOW()
        );
        settlementDeadline = tradingDeadline + settlementWindow;

        // Deploy Market
        newMarketProxy = factory.deployNewMarketProxy({
            initialLiquidity_: initialLiquidity,
            newMarketMetadata_: IDelphiMarket.VerifiableUri({
                uri: "ipfs://dummyUri", uriContentHash: keccak256(abi.encodePacked("dummyUriContent"))
            }),
            newMarketInitializationCalldata_: abi.encode(
                IDynamicParimutuelMarketTypes.MarketConfig({
                    outcomeCount: outcomeCount,
                    k: bound(args.k, implementation.MIN_K(), implementation.MAX_K()),
                    tradingFee: bound(
                        args.tradingFee, implementation.MIN_TRADING_FEE(), implementation.MAX_TRADING_FEE()
                    ),
                    tradingDeadline: tradingDeadline,
                    settlementDeadline: settlementDeadline
                })
            )
        });
    }

    function _deal(IERC20Metadata token, address recipient, uint256 desiredBalance) internal {
        // Get recipient balance
        uint256 recipientBalance = token.balanceOf(recipient);

        // If recipient balance is below desired balance
        if (recipientBalance < desiredBalance) {
            // Switch to ADMIN
            _useNewSender(ADMIN);

            // Mint tokens to recipient
            IUsdc(address(token)).mint({to: recipient, amount: desiredBalance - recipientBalance});
        }
    }
}
