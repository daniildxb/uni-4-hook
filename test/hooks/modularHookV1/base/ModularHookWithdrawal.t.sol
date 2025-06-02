// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ModularHookBaseTest} from "./ModularHookBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";

/**
 * @title ModularHookWithdrawalTest
 * @notice Tests for withdrawal functionality in ModularHookV1
 */
contract ModularHookWithdrawalTest is ModularHookBaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    /**
     * @notice Tests basic withdrawal functionality
     * Verifies that users can withdraw their full deposits successfully
     */
    function test_basic_withdrawal() public {
        // User deposits
        (uint256 shares,, int128 deposited0, int128 deposited1) =
            depositTokensToHook(depositAmount0(), depositAmount1(), user1);

        // Record initial balances
        uint256 user1Token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1Before = IERC20(token1Address).balanceOf(user1);

        // User withdraws all shares
        vm.startPrank(user1);
        hook.redeem(shares, user1, user1);
        vm.stopPrank();

        // Check final balances
        uint256 user1Token0After = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1After = IERC20(token1Address).balanceOf(user1);

        uint256 token0Withdrawn = user1Token0After - user1Token0Before;
        uint256 token1Withdrawn = user1Token1After - user1Token1Before;

        console.log("Token0 withdrawn:", token0Withdrawn);
        console.log("Token1 withdrawn:", token1Withdrawn);

        // User should get back approximately what they deposited (minus any rounding errors)

        assertLe(token0Withdrawn, uint256(int256(deposited0)), "Should withdraw no more than deposited token0 amount");
        assertLe(token1Withdrawn, uint256(int256(deposited1)), "Should withdraw no more than deposited token1 amount");
        assertApproxEqAbs(
            token0Withdrawn,
            uint256(int256(deposited0)),
            scaleToken1Amount(1),
            "Should lose no more than 1 token to slippage on withdraw"
        );
        assertApproxEqAbs(
            token1Withdrawn,
            uint256(int256(deposited1)),
            scaleToken1Amount(1),
            "Should lose no more than 1 token to slippage on withdraw"
        );

        // User should have no shares left
        assertEq(IERC20(address(hook)).balanceOf(user1), 0, "User should have no shares remaining");
    }

    /**
     * @notice Tests partial withdrawal functionality
     * Verifies that users can withdraw only part of their shares
     */
    function test_partial_withdrawal() public {
        // User deposits
        (uint256 shares,,,) = depositTokensToHook(depositAmount0(), depositAmount1(), user1);

        // User withdraws half their shares
        uint256 sharesToWithdraw = shares / 2;

        uint256 user1Token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1Before = IERC20(token1Address).balanceOf(user1);

        vm.startPrank(user1);
        hook.redeem(sharesToWithdraw, user1, user1);
        vm.stopPrank();

        uint256 user1Token0After = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1After = IERC20(token1Address).balanceOf(user1);

        uint256 token0Withdrawn = user1Token0After - user1Token0Before;
        uint256 token1Withdrawn = user1Token1After - user1Token1Before;

        console.log("Partial token0 withdrawn:", token0Withdrawn);
        console.log("Partial token1 withdrawn:", token1Withdrawn);

        // User should get back approximately half of what they deposited
        // allowing 0.01% delta
        assertApproxEqRel(
            token0Withdrawn, depositAmount0() / 2, 1e14, "Should withdraw approximately half deposited token0 amount"
        );
        assertApproxEqRel(
            token1Withdrawn, depositAmount1() / 2, 1e14, "Should withdraw approximately half deposited token1 amount"
        );

        // User should have approximately half their shares left
        uint256 remainingShares = IERC20(address(hook)).balanceOf(user1);
        assertApproxEqAbs(remainingShares, shares - sharesToWithdraw, 1, "User should have remaining shares");

        // User can withdraw the rest
        vm.startPrank(user1);
        hook.redeem(remainingShares, user1, user1);
        vm.stopPrank();

        // All shares should be gone
        assertEq(
            IERC20(address(hook)).balanceOf(user1), 0, "User should have no shares remaining after full withdrawal"
        );
    }

    /**
     * @notice Tests withdrawal with multiple users
     * Verifies that withdrawals work correctly when multiple users have positions
     */
    function test_withdrawal_with_multiple_users() public {
        // Both users deposit
        (uint256 user1Shares,,,) = depositTokensToHook(depositAmount0(), depositAmount1(), user1);
        (uint256 user2Shares,,,) = depositTokensToHook(depositAmount0() * 2, depositAmount1() * 2, user2);

        // Verify shares are proportional
        // allow some slippage due to inconsistent deposit sizes
        assertApproxEqAbs(user2Shares, user1Shares * 2, 100, "User2 should have approximately 2x shares of User1");

        // User1 withdraws first
        uint256 user1Token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1Before = IERC20(token1Address).balanceOf(user1);

        vm.startPrank(user1);
        hook.redeem(user1Shares, user1, user1);
        vm.stopPrank();

        uint256 user1Token0After = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1After = IERC20(token1Address).balanceOf(user1);

        uint256 user1Token0Withdrawn = user1Token0After - user1Token0Before;
        uint256 user1Token1Withdrawn = user1Token1After - user1Token1Before;

        // User2 withdraws second
        uint256 user2Token0Before = IERC20(token0Address).balanceOf(user2);
        uint256 user2Token1Before = IERC20(token1Address).balanceOf(user2);

        vm.startPrank(user2);
        hook.redeem(user2Shares, user2, user2);
        vm.stopPrank();

        uint256 user2Token0After = IERC20(token0Address).balanceOf(user2);
        uint256 user2Token1After = IERC20(token1Address).balanceOf(user2);

        uint256 user2Token0Withdrawn = user2Token0After - user2Token0Before;
        uint256 user2Token1Withdrawn = user2Token1After - user2Token1Before;

        console.log("User1 token0 withdrawn:", user1Token0Withdrawn);
        console.log("User1 token1 withdrawn:", user1Token1Withdrawn);
        console.log("User2 token0 withdrawn:", user2Token0Withdrawn);
        console.log("User2 token1 withdrawn:", user2Token1Withdrawn);

        // Verify proportional withdrawals
        assertLe(
            user1Token0Withdrawn, depositAmount0(), "User1 should withdraw no more than deposited token0 amount"
        );
        assertLe(
            user1Token1Withdrawn, depositAmount1(), "User1 should withdraw no more than deposited token1 amount"
        );
        assertLe(
            user2Token0Withdrawn, depositAmount0() * 2, "User2 should withdraw no more than deposited token0 amount"
        );
        assertLe(
            user2Token1Withdrawn, depositAmount1() * 2, "User2 should withdraw no more than deposited token1 amount"
        );
        assertApproxEqAbs(user1Token0Withdrawn, depositAmount0(), scaleToken0Amount(1), "User1 should withdraw deposited token0 amount");
        assertApproxEqAbs(user1Token1Withdrawn, depositAmount1(), scaleToken1Amount(1), "User1 should withdraw deposited token1 amount");
        assertApproxEqAbs(
            user2Token0Withdrawn, depositAmount0() * 2, scaleToken0Amount(1), "User2 should withdraw 2x deposited token0 amount"
        );
        assertApproxEqAbs(
            user2Token1Withdrawn, depositAmount1() * 2, scaleToken1Amount(1), "User2 should withdraw 2x deposited token1 amount"
        );

        // Both users should have no shares left
        assertEq(IERC20(address(hook)).balanceOf(user1), 0, "User1 should have no shares remaining");
        assertEq(IERC20(address(hook)).balanceOf(user2), 0, "User2 should have no shares remaining");
    }

    /**
     * @notice Tests withdrawal after swaps have occurred
     * Verifies that withdrawals work correctly after swap fees have accrued
     */
    function test_withdrawal_after_swaps() public {
        // User deposits
        (uint256 shares,,,) = depositTokensToHook(depositAmount0() * 5, depositAmount1() * 5, user1);

        // Execute multiple swaps to generate fees
        for (uint256 i = 0; i < 3; i++) {
            bool zeroForOne = i % 2 == 0;
            int256 swapAmount = zeroForOne ? int256(depositAmount0() / 10) : int256(depositAmount1() / 10);

            executeSwap(zeroForOne, -swapAmount);
        }

        // Withdrawal after swaps
        uint256 user1Token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1Before = IERC20(token1Address).balanceOf(user1);
        uint256 shareValueBefore = hook.convertToAssets(shares);

        console.log("Share value before withdrawal:", shareValueBefore);

        vm.startPrank(user1);
        hook.redeem(shares, user1, user1);
        vm.stopPrank();

        uint256 user1Token0After = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1After = IERC20(token1Address).balanceOf(user1);

        uint256 token0Withdrawn = user1Token0After - user1Token0Before;
        uint256 token1Withdrawn = user1Token1After - user1Token1Before;

        console.log("Token0 withdrawn after swaps:", token0Withdrawn);
        console.log("Token1 withdrawn after swaps:", token1Withdrawn);

        // User should get back at least what they deposited (potentially more due to fees)
        // todo: add proper check
        // assertGe(
        //     token0Withdrawn + token1Withdrawn,
        //     depositAmount * 5 * 2 - 50,
        //     "Should withdraw at least deposited amount minus small rounding"
        // );
    }

    /**
     * @notice Tests emergency withdrawal scenarios
     * Verifies that withdrawals work even in edge cases
     * todo: wtf is this test case
     */
    function test_emergency_withdrawal_scenarios() public {
        // User deposits minimal amount
        (uint256 shares,,,) = depositTokensToHook(depositAmount0(), depositAmount1(), user1);

        // Verify minimal withdrawal works
        vm.startPrank(user1);
        uint256 token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 token1Before = IERC20(token1Address).balanceOf(user1);

        hook.redeem(shares, user1, user1);

        uint256 token0After = IERC20(token0Address).balanceOf(user1);
        uint256 token1After = IERC20(token1Address).balanceOf(user1);
        vm.stopPrank();

        // Should get some tokens back
        // todo: check amounts
        assertGt(token0After, token0Before, "Should receive some token0 back");
        assertGt(token1After, token1Before, "Should receive some token1 back");

        // User should have no shares left
        assertEq(IERC20(address(hook)).balanceOf(user1), 0, "User should have no shares remaining");
    }

    /**
     * @notice Tests withdrawal with different recipient
     * Verifies that withdrawals can be sent to a different address
     */
    function test_withdrawal_to_different_recipient() public {
        // User1 deposits
        (uint256 shares,,,) = depositTokensToHook(depositAmount0(), depositAmount1(), user1);

        address recipient = address(0x9999);

        // Record initial balances
        uint256 recipientToken0Before = IERC20(token0Address).balanceOf(recipient);
        uint256 recipientToken1Before = IERC20(token1Address).balanceOf(recipient);
        uint256 user1Token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1Before = IERC20(token1Address).balanceOf(user1);

        // User1 withdraws to recipient
        vm.startPrank(user1);
        hook.redeem(shares, recipient, user1);
        vm.stopPrank();

        // Check balances after withdrawal
        uint256 recipientToken0After = IERC20(token0Address).balanceOf(recipient);
        uint256 recipientToken1After = IERC20(token1Address).balanceOf(recipient);
        uint256 user1Token0After = IERC20(token0Address).balanceOf(user1);
        uint256 user1Token1After = IERC20(token1Address).balanceOf(user1);

        // Recipient should receive the tokens
        assertGt(recipientToken0After - recipientToken0Before, 0, "Recipient should receive token0");
        assertGt(recipientToken1After - recipientToken1Before, 0, "Recipient should receive token1");

        // User1's balance should not change
        assertEq(user1Token0After, user1Token0Before, "User1's token0 balance should not change");
        assertEq(user1Token1After, user1Token1Before, "User1's token1 balance should not change");

        // User1 should have no shares left
        assertEq(IERC20(address(hook)).balanceOf(user1), 0, "User1 should have no shares remaining");
    }

    /**
     * @notice Tests that withdrawal fails with insufficient shares
     */
    function test_withdrawal_fails_with_insufficient_shares() public {
        // User deposits
        (uint256 shares,,,) = depositTokensToHook(depositAmount0(), depositAmount1(), user1);

        // Try to withdraw more shares than owned
        vm.startPrank(user1);
        vm.expectRevert();
        hook.redeem(shares + 1, user1, user1);
        vm.stopPrank();

        // Try to withdraw from empty account
        vm.startPrank(user2);
        vm.expectRevert();
        hook.redeem(1, user2, user2);
        vm.stopPrank();
    }
}
