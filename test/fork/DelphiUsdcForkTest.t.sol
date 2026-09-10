// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Interfaces
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

// Contracts
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";

interface IUsdc {
    function owner() external view returns (address);
    function updateMasterMinter(address _newMasterMinter) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function mint(address to, uint256 amount) external;
}

contract Delphi_Usdc_Fork_Test is DelphiTestUtils {
    // Immutables
    address immutable ADMIN = makeAddr("ADMIN");
    address immutable USER = makeAddr("USER");

    // Other
    // forge-lint: disable-next-line(unsafe-cheatcode)
    string networksConfigToml = vm.readFile("config/networks.toml");

    // Structs
    struct Args {
        ILmsrMarket.MarketConfig marketConfig;
        uint256 initialDeposit;
        uint256 outcomeIdx;
        uint256 sharesDelta;
        bool redeem;
    }

    // Libraries
    using LmsrMath for uint256;

    // Tests

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_Fork_GensynTestnet(Args calldata args, DelphiConfig memory delphiConfig) external {
        _test({networkAlias: "gensyn-testnet", args: args, delphiConfig: delphiConfig});
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_Fork_GensynMainnet(Args calldata args, DelphiConfig memory delphiConfig) external {
        _test({networkAlias: "gensyn-mainnet", args: args, delphiConfig: delphiConfig});
    }

    // Internal Utils
    function _test(string memory networkAlias, Args calldata args, DelphiConfig memory delphiConfig) internal {
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

        // Override delphi config token
        delphiConfig.token = IERC20Metadata(address(usdc));

        // Deploy Delphi
        DelphiAddresses memory deployment = _boundAndDeployDelphi({delphiConfig: delphiConfig});

        // Deploy mock oracle relayer
        MockOracleRelayer mockOracleRelayer = new MockOracleRelayer(deployment.gateway);

        // Switch to GATEWAY_OWNER
        _useNewSender(GATEWAY_OWNER);

        // Set oracle relayer on gateway
        deployment.gateway.setOracleRelayer(address(mockOracleRelayer));

        // Deploy Market
        ILmsrMarket newMarketProxy = _boundAndDeployMarket({
            marketConfig: args.marketConfig, deployment: deployment, token: usdc, initialDeposit: args.initialDeposit
        });

        // Get market
        ILmsrMarket.Market memory market = newMarketProxy.getMarket();

        // Get vars
        uint256 outcomeCount = market.config.outcomeCount;
        uint256 earliestResolveTime = market.config.earliestResolveTime;
        uint256 settlementDeadline = market.config.settlementDeadline;

        // Pick shares delta
        uint256 sharesDelta = bound(args.sharesDelta, deployment.gateway.MIN_SHARES_DELTA(), 1_000_000_000_000e6);

        // Pick outcome idx
        uint256 outcomeIdx = bound(args.outcomeIdx, 0, outcomeCount - 1);

        // Get quote
        try deployment.gateway
            .quoteBuyExactOut({
                marketProxy: ILmsrMarket(newMarketProxy), outcomeIdx: outcomeIdx, sharesOut: sharesDelta
            }) returns (
            uint256 tokensIn, uint256, uint256
        ) {
            // Deal tokensIn to USER
            _deal({token: usdc, recipient: USER, desiredBalance: tokensIn});

            // Switch to USER
            _useNewSender(USER);

            // Approve market to pull USER tokens
            usdc.approve(address(newMarketProxy), tokensIn);

            // User buys
            deployment.gateway
                .buyExactOut({
                    marketProxy: newMarketProxy,
                    outcomeIdx: outcomeIdx,
                    sharesOut: sharesDelta,
                    maxTokensIn: type(uint256).max
                });

            // User sells
            try deployment.gateway
                .sellExactIn({
                    marketProxy: newMarketProxy, outcomeIdx: outcomeIdx, sharesIn: sharesDelta, minTokensOut: 0
                }) {
                // Deal tokensIn to USER
                _deal({token: usdc, recipient: USER, desiredBalance: tokensIn});

                // Switch to USER
                _useNewSender(USER);

                // Approve market to pull USER tokens
                usdc.approve(address(newMarketProxy), tokensIn);

                // User buys again (to have shares to redeem or liquidate later)
                deployment.gateway
                    .buyExactOut({
                        marketProxy: newMarketProxy,
                        outcomeIdx: outcomeIdx,
                        sharesOut: sharesDelta,
                        maxTokensIn: type(uint256).max
                    });

                // If redeem
                if (args.redeem) {
                    // Warp to earliest resolve time
                    vm.warp(earliestResolveTime);

                    // Settle market via mock oracle relayer
                    mockOracleRelayer.setOutcome(address(newMarketProxy), outcomeIdx);
                    mockOracleRelayer.setOracleFeeRecipient(address(this));
                    deployment.gateway.resolveMarket(address(newMarketProxy));

                    // Redeem
                    deployment.gateway.redeem({marketProxy: newMarketProxy});

                    // If not redeem
                } else {
                    // Warp past settlement deadline
                    vm.warp(settlementDeadline + 1);

                    // Build outcome indices
                    uint256[] memory outcomeIndices = new uint256[](1);
                    outcomeIndices[0] = outcomeIdx;

                    // Liquidate
                    deployment.gateway.liquidate({marketProxy: newMarketProxy, outcomeIndices: outcomeIndices});
                }

                // Do nothing for now
            } catch (bytes memory err) {
                // _handleCatch(err, ILmsrGatewayErrors.TokensOutBelowMin.selector);
                _handleCatch(err, _quoteSellExactInAllowedErrors());
            }
        } catch (bytes memory err) {
            _handleCatch(err, _quoteBuyExactOutAllowedErrors());
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
