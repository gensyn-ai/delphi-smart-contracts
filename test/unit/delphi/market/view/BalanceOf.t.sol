// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {DelphiTestUtils} from "test/support/utils/DelphiTestUtils.t.sol";

// Contracts
import {MockToken} from "test/support/mocks/MockToken.sol";
import {MockOracleRelayer} from "test/support/mocks/MockOracleRelayer.sol";

// Interfaces
import {ILmsrMarket} from "src/lmsr/implementation/ILmsrMarket.sol";

contract LmsrMarket_BalanceOf_Test is DelphiTestUtils {
    // State Variables
    MockToken token;
    DelphiAddresses deployment;
    MockOracleRelayer oracleRelayer;
    ILmsrMarket marketProxy;

    // Immutables
    address immutable BUYER = makeAddr("BUYER");

    // Tests

    /// @dev ERC-6909 getters return zero for unconfigured outcome ids (they do not revert),
    ///      matching the EIP reference implementation and common integrator expectations.
    function testFuzz_BalanceOf_OutcomeIsOutOfBounds_ReturnsZero(
        uint8 tokenDecimals,
        DelphiConfig memory delphiConfig,
        ILmsrMarket.MarketConfig memory marketConfig,
        uint256 initialDeposit,
        uint256 boughtOutcomeIdx,
        uint256 sharesOut,
        uint256 invalidOutcomeIdx
    ) external {
        // Deploy
        (token, deployment, oracleRelayer, marketProxy) = _deployBoundedTokenAndDelphiAndMarket({
            tokenDecimals: tokenDecimals,
            delphiConfig: delphiConfig,
            marketConfig: marketConfig,
            initialDeposit: initialDeposit
        });

        // Bound bought outcome idx and shares out
        uint256 outcomeCount = marketProxy.getMarket().config.outcomeCount;
        boughtOutcomeIdx = bound(boughtOutcomeIdx, 0, outcomeCount - 1);
        sharesOut = bound(
            sharesOut,
            deployment.gateway.MIN_SHARES_DELTA(),
            _maxSharesOut({marketProxy_: marketProxy, outcomeIdx: boughtOutcomeIdx})
        );

        // Buy shares (so the buyer holds a nonzero valid-outcome balance, distinguishing "invalid" from "empty")
        uint256 tokensIn = _quoteBuyOrSkip(deployment.gateway, marketProxy, boughtOutcomeIdx, sharesOut);
        _useNewSender(BUYER);
        deal(address(token), BUYER, tokensIn);
        token.approve(address(marketProxy), tokensIn);
        _useNewSender(address(deployment.gateway));
        marketProxy.buy({buyer: BUYER, outcomeIdx: boughtOutcomeIdx, tokensIn: tokensIn, sharesOut: sharesOut});

        // Sanity check: the buyer holds the bought shares
        assertEq(marketProxy.balanceOf(BUYER, boughtOutcomeIdx), sharesOut, "valid outcome balance mismatch");

        // Bound invalid outcome idx out of the configured range
        invalidOutcomeIdx = bound(invalidOutcomeIdx, outcomeCount, type(uint256).max);

        // An unconfigured outcome id returns a zero balance (no revert)
        assertEq(marketProxy.balanceOf(BUYER, invalidOutcomeIdx), 0, "invalid outcome balance != 0");
    }
}
