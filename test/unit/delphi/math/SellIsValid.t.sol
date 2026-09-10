// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Inheritance
import {Test} from "forge-std/Test.sol";

// Contracts
import {LmsrMathHarness} from "test/support/harnesses/LmsrMathHarness.sol";

// Interfaces
import {ILmsrMathErrors} from "src/lmsr/math/ILmsrMathErrors.sol";

// Libraries
import {LmsrMath} from "src/lmsr/math/LmsrMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LmsrMath_SellIsValid_Test is Test {
    // ===== CONSTANTS =====
    // Todo: Get these dynamically from the LmsrMarket implementation

    // Implementation
    uint256 public constant MIN_B = 1e18; // 1
    uint256 public constant MAX_B = 5_000_000e18; // 5M

    // Gateway
    uint256 public constant MIN_SHARES_DELTA = 0.01e18;

    // Libraries
    using Math for uint256;

    // State variables
    LmsrMathHarness public lmsrMathHarness;

    // Setup
    function setUp() public {
        lmsrMathHarness = new LmsrMathHarness();
    }

    // Tests
    function testFuzz_SellIsValid_ZeroSharesIn_Reverts(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 tokensOut,
        uint256 tokenDecimalScaler
    ) external {
        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMathErrors.ZeroSharesIn.selector));

        // Call sell is valid
        lmsrMathHarness.sellIsValid({
            b: b,
            currentExpSum: currentExpSum,
            modelCurrentSupply: modelCurrentSupply,
            sharesIn: 0,
            tokensOut: tokensOut,
            tokenDecimalScaler: tokenDecimalScaler
        });
    }

    function testFuzz_SellIsValid_SharesInExceedSupply_Reverts(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 sharesIn,
        uint256 tokensOut,
        uint256 tokenDecimalScaler
    ) external {
        // Bound model current supply
        modelCurrentSupply = bound(modelCurrentSupply, 0, type(uint256).max - 1);

        // Bound shares in
        sharesIn = bound(sharesIn, modelCurrentSupply + 1, type(uint256).max);

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrMathErrors.SharesInExceedSupply.selector, sharesIn, modelCurrentSupply)
        );

        // Call sell is valid
        lmsrMathHarness.sellIsValid({
            b: b,
            currentExpSum: currentExpSum,
            modelCurrentSupply: modelCurrentSupply,
            sharesIn: sharesIn,
            tokensOut: tokensOut,
            tokenDecimalScaler: tokenDecimalScaler
        });
    }

    function testFuzz_SellIsValid_ZeroTokensOut_Reverts(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 sharesIn,
        uint256 tokenDecimalScaler
    ) external {
        // Bound model current supply
        modelCurrentSupply = bound(modelCurrentSupply, 2, type(uint256).max);

        // Bound shares in
        sharesIn = bound(sharesIn, 1, modelCurrentSupply - 1);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMathErrors.ZeroTokensOut.selector));

        // Call sell is valid
        lmsrMathHarness.sellIsValid({
            b: b,
            currentExpSum: currentExpSum,
            modelCurrentSupply: modelCurrentSupply,
            sharesIn: sharesIn,
            tokensOut: 0,
            tokenDecimalScaler: tokenDecimalScaler
        });
    }

    // Note: To solve stack depth issues
    struct SellIsValidArgs {
        uint256 tokenDecimals;
        uint256 outcomeCount;
        uint256 b;
        uint256 currentExpSum;
        uint256 modelCurrentSupply;
        uint256 sharesIn;
        uint256 tokensOut;
    }

    function testFuzz_SellIsValid_Success(SellIsValidArgs memory args) external view {
        // Bound token decimals
        args.tokenDecimals = bound(args.tokenDecimals, 6, 18);

        // Calculate token decimal scaler
        uint256 tokenDecimalScaler = 10 ** (18 - args.tokenDecimals);

        // Bound outcome count
        args.outcomeCount = bound(args.outcomeCount, 2, 20);

        // Bound b
        args.b = bound(args.b, MIN_B, MAX_B);

        // Bound outcome supply
        args.modelCurrentSupply = bound(args.modelCurrentSupply, MIN_SHARES_DELTA, _outcomeMaxSupply(args.b));

        // Calculate outcome exp
        uint256 outcomeCurrentExp = LmsrMath.outcomeExp(args.b, args.modelCurrentSupply);

        // Bound current exp sum
        args.currentExpSum = bound(
            args.currentExpSum,
            _minExpSum(args.outcomeCount, outcomeCurrentExp),
            _maxExpSum(args.outcomeCount, outcomeCurrentExp)
        );

        // Bound shares in
        args.sharesIn = bound(args.sharesIn, MIN_SHARES_DELTA, args.modelCurrentSupply);

        // Calculate expected new exp sum
        uint256 outcomeNewExp = lmsrMathHarness.outcomeExp(args.b, args.modelCurrentSupply - args.sharesIn);
        uint256 expectedNewExpSum = args.currentExpSum + outcomeNewExp - outcomeCurrentExp;

        // Calculate max tokens out
        uint256 maxTokensOut = _maxTokensOut({
            b: args.b,
            currentExpSum: args.currentExpSum,
            newExpSum: expectedNewExpSum,
            tokenDecimalScaler: tokenDecimalScaler
        });

        // Ensure max tokens out is greater than 0
        vm.assume(maxTokensOut > 0);

        // Bound tokens out
        args.tokensOut = bound(args.tokensOut, 1, maxTokensOut);

        // Call sell is valid
        (uint256 newExpSum, bool valid) = lmsrMathHarness.sellIsValid({
            b: args.b,
            currentExpSum: args.currentExpSum,
            modelCurrentSupply: args.modelCurrentSupply,
            sharesIn: args.sharesIn,
            tokensOut: args.tokensOut,
            tokenDecimalScaler: tokenDecimalScaler
        });

        // Validate
        assertEq(newExpSum, expectedNewExpSum, "unexpected new expSum");
        assertTrue(valid, "invalid sell");
    }

    /* Calculate outcome max supply
     * e^(outcomeSupply / b) <= MAX_EXP_INPUT
     * outcomeSupply / b <= ln(MAX_EXP_INPUT)
     * outcomeSupply <= ln(MAX_EXP_INPUT) * b
     */
    function _outcomeMaxSupply(uint256 b) internal view returns (uint256) {
        return lmsrMathHarness._computeLn(LmsrMath.MAX_EXP_INPUT).mulDiv(b, 1e18, Math.Rounding.Ceil);
    }

    /* Calculate min exp sum
     * minExpSum = (minOutcomeExp * (outcomeCount - 1)) + outcomeCurrentExp
     * minExpSum = 1e18 * (outcomeCount - 1) + outcomeCurrentExp
     */
    function _minExpSum(uint256 outcomeCount, uint256 outcomeCurrentExp) internal pure returns (uint256) {
        return 1e18 * (outcomeCount - 1) + outcomeCurrentExp;
    }

    /* Calculate max exp sum
     * maxExpSum = (maxOutcomeExp * (outcomeCount - 1)) + outcomeCurrentExp
     * maxExpSum = e^(MAX_EXP_INPUT) * (outcomeCount - 1) + outcomeCurrentExp
     */
    function _maxExpSum(uint256 outcomeCount, uint256 outcomeCurrentExp) internal view returns (uint256) {
        return (lmsrMathHarness.computeExp(LmsrMath.MAX_EXP_INPUT) * (outcomeCount - 1)) + outcomeCurrentExp;
    }

    /* Calculate min tokens in
     * tokensOut * tokenDecimalScaler * 1e18 <= b * ratioLnLowerBound
     * tokensOut <= (b * ratioLnLowerBound) / (tokenDecimalScaler * 1e18)
     */
    function _maxTokensOut(uint256 b, uint256 currentExpSum, uint256 newExpSum, uint256 tokenDecimalScaler)
        internal
        view
        returns (uint256 maxTokensOut)
    {
        uint256 currentExpSumLowerBound = lmsrMathHarness.getExpLowerBound(currentExpSum);
        uint256 newExpSumUpperBound = lmsrMathHarness.getExpUpperBound(newExpSum);
        vm.assume(newExpSumUpperBound < currentExpSumLowerBound);
        uint256 ratio = currentExpSumLowerBound.mulDiv(1e18, newExpSumUpperBound, Math.Rounding.Floor);
        try lmsrMathHarness.computeLnLowerBound(ratio) returns (uint256 ratioLnLowerBound) {
            maxTokensOut = b.mulDiv(ratioLnLowerBound, tokenDecimalScaler * 1e18, Math.Rounding.Floor);
        } catch {
            maxTokensOut = 0;
        }
    }
}
