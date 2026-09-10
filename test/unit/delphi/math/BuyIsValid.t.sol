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

contract LmsrMath_BuyIsValid_Test is Test {
    // Libraries
    using Math for uint256;

    // ===== CONSTANTS =====
    // Todo: Get these dynamically from the LmsrMarket implementation

    // Implementation
    uint256 public constant MIN_B = 1e18; // 1
    uint256 public constant MAX_B = 5_000_000e18; // 5M

    // Gateway
    uint256 public constant MIN_SHARES_DELTA = 0.01e18;

    // State variables
    LmsrMathHarness public lmsrMathHarness;

    // Setup
    function setUp() public {
        lmsrMathHarness = new LmsrMathHarness();
    }

    // Tests
    function testFuzz_BuyIsValid_ZeroTokensIn_Reverts(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 sharesOut,
        uint256 tokenDecimalScaler
    ) external {
        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMathErrors.ZeroTokensIn.selector));

        // Call buy is valid
        lmsrMathHarness.buyIsValid({
            b: b,
            currentExpSum: currentExpSum,
            modelCurrentSupply: modelCurrentSupply,
            tokensIn: 0,
            sharesOut: sharesOut,
            tokenDecimalScaler: tokenDecimalScaler
        });
    }

    function testFuzz_BuyIsValid_ZeroSharesOut_Reverts(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 tokensIn,
        uint256 tokenDecimalScaler
    ) external {
        // Bound tokens in
        tokensIn = bound(tokensIn, 1, type(uint256).max);

        // Expect Revert
        vm.expectRevert(abi.encodeWithSelector(ILmsrMathErrors.ZeroSharesOut.selector));

        // Call buy is valid
        lmsrMathHarness.buyIsValid({
            b: b,
            currentExpSum: currentExpSum,
            modelCurrentSupply: modelCurrentSupply,
            tokensIn: tokensIn,
            sharesOut: 0,
            tokenDecimalScaler: tokenDecimalScaler
        });
    }

    function testFuzz_BuyIsValid_ExpTooBig_Reverts(
        uint256 b,
        uint256 currentExpSum,
        uint256 modelCurrentSupply,
        uint256 tokensIn,
        uint256 sharesOut,
        uint256 tokenDecimalScaler
    ) external {
        // Bound b
        b = bound(b, MIN_B, MAX_B);

        // Bound model current supply to a valid exp input (so the new supply is the one that overflows)
        modelCurrentSupply = bound(modelCurrentSupply, 0, LmsrMath.MAX_EXP_INPUT.mulDiv(b, 1e18));

        // Calculate the minimum new supply that makes the exp input exceed MAX_EXP_INPUT
        // newExpInput > MAX_EXP_INPUT
        // (modelCurrentSupply + sharesOut).mulDiv(1e18, b) > MAX_EXP_INPUT
        // modelCurrentSupply + sharesOut >= (MAX_EXP_INPUT + 1).mulDiv(b, 1e18, Ceil)
        uint256 minNewSupply = (LmsrMath.MAX_EXP_INPUT + 1).mulDiv(b, 1e18, Math.Rounding.Ceil);

        // Bound shares out (so the new supply is too big)
        uint256 minSharesOut = minNewSupply > modelCurrentSupply ? minNewSupply - modelCurrentSupply : 1;
        sharesOut = bound(sharesOut, minSharesOut, type(uint256).max - modelCurrentSupply);

        // Bound tokens in (so it passes the zero check)
        tokensIn = bound(tokensIn, 1, type(uint256).max);

        // Calculate the expected exp input
        uint256 expInput = (modelCurrentSupply + sharesOut).mulDiv(1e18, b);
        assertGt(expInput, LmsrMath.MAX_EXP_INPUT, "exp input not big enough");

        // Expect Revert
        vm.expectRevert(
            abi.encodeWithSelector(ILmsrMathErrors.ExpInputTooBig.selector, expInput, LmsrMath.MAX_EXP_INPUT)
        );

        // Call buy is valid
        lmsrMathHarness.buyIsValid({
            b: b,
            currentExpSum: currentExpSum,
            modelCurrentSupply: modelCurrentSupply,
            tokensIn: tokensIn,
            sharesOut: sharesOut,
            tokenDecimalScaler: tokenDecimalScaler
        });
    }

    // Note: To solve stack depth issues
    struct BuyIsValidArgs {
        uint256 tokenDecimals;
        uint256 outcomeCount;
        uint256 b;
        uint256 currentExpSum;
        uint256 modelCurrentSupply;
        uint256 tokensIn;
        uint256 sharesOut;
    }

    function testFuzz_BuyIsValid_Success(BuyIsValidArgs memory args) external view {
        // Bound token decimals
        args.tokenDecimals = bound(args.tokenDecimals, 6, 18);

        // Calculate token decimal scaler
        uint256 tokenDecimalScaler = 10 ** (18 - args.tokenDecimals);

        // Bound outcome count
        args.outcomeCount = bound(args.outcomeCount, 2, 20);

        // Bound b
        args.b = bound(args.b, MIN_B, MAX_B);

        // Bound outcome supply
        args.modelCurrentSupply = bound(args.modelCurrentSupply, 0, _outcomeMaxSupplyBeforeBuy(args.b));

        // Ensure
        if (args.modelCurrentSupply > 0 && args.modelCurrentSupply < MIN_SHARES_DELTA) {
            args.modelCurrentSupply = MIN_SHARES_DELTA;
        }

        // Calculate outcome exp
        uint256 outcomeCurrentExp = LmsrMath.outcomeExp(args.b, args.modelCurrentSupply);

        // Bound current exp sum
        args.currentExpSum = bound(
            args.currentExpSum,
            _minExpSum(args.outcomeCount, outcomeCurrentExp),
            _maxExpSum(args.outcomeCount, outcomeCurrentExp)
        );

        // Bound shares out
        args.sharesOut = bound(args.sharesOut, MIN_SHARES_DELTA, _outcomeMaxSupply(args.b) - args.modelCurrentSupply);

        // Calculate expected new exp sum
        uint256 outcomeNewExp = lmsrMathHarness.outcomeExp(args.b, args.modelCurrentSupply + args.sharesOut);
        uint256 expectedNewExpSum = args.currentExpSum + outcomeNewExp - outcomeCurrentExp;

        // Bound tokens in
        args.tokensIn = bound(
            args.tokensIn,
            _minTokensIn(args.b, expectedNewExpSum, args.currentExpSum, tokenDecimalScaler),
            _maxTokensIn(tokenDecimalScaler)
        );

        // Call buy is valid
        (uint256 newExpSum, bool valid) = lmsrMathHarness.buyIsValid({
            b: args.b,
            currentExpSum: args.currentExpSum,
            modelCurrentSupply: args.modelCurrentSupply,
            tokensIn: args.tokensIn,
            sharesOut: args.sharesOut,
            tokenDecimalScaler: tokenDecimalScaler
        });

        // Validate
        assertEq(newExpSum, expectedNewExpSum, "unexpected new expSum");
        assertTrue(valid, "invalid buy");
    }

    /* Calculate outcome max supply
     * e^(outcomeSupply / b) <= MAX_EXP_INPUT
     * outcomeSupply / b <= ln(MAX_EXP_INPUT)
     * outcomeSupply <= ln(MAX_EXP_INPUT) * b
     */
    function _outcomeMaxSupply(uint256 b) internal view returns (uint256) {
        return lmsrMathHarness._computeLn(LmsrMath.MAX_EXP_INPUT).mulDiv(b, 1e18, Math.Rounding.Ceil);
    }

    /* modelCurrentSupply + minSharesDelta <= maxSupply
     * modelCurrentSupply <= maxSupply - minSharesDelta
     */
    function _outcomeMaxSupplyBeforeBuy(uint256 b) internal view returns (uint256) {
        return _outcomeMaxSupply(b) - MIN_SHARES_DELTA;
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
     * tokensIn * tokenDecimalScaler * 1e18 >= b * ratioLnUpperBound
     * tokensIn >= b * ratioLnUpperBound / (tokenDecimalScaler * 1e18)
     */
    function _minTokensIn(uint256 b, uint256 newExpSum, uint256 currentExpSum, uint256 tokenDecimalScaler)
        internal
        view
        returns (uint256 minTokensIn)
    {
        uint256 newExpSumUpperBound = lmsrMathHarness.getExpUpperBound(newExpSum); // Note: Up (against user)
        uint256 currentExpSumLowerBound = lmsrMathHarness.getExpLowerBound(currentExpSum); // Note: Down (against user)
        uint256 ratio = newExpSumUpperBound.mulDiv(1e18, currentExpSumLowerBound, Math.Rounding.Ceil);
        uint256 ratioLnUpperBound = lmsrMathHarness.computeLnUpperBound(ratio);
        minTokensIn = (b * ratioLnUpperBound).ceilDiv(tokenDecimalScaler * 1e18);
    }

    /* tokensIn * tokenDecimalScaler * 1e18 <= type(uint256).max
     * tokensIn <= type(uint256).max / (tokenDecimalScaler * 1e18)
     */
    function _maxTokensIn(uint256 tokenDecimalScaler) internal pure returns (uint256) {
        return type(uint256).max / (tokenDecimalScaler * 1e18);
    }
}
