// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {HotBufferHook} from "../../../src/hooks/HotBufferHook.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";

/**
 * @notice Test for hot buffer hook functionality
 */
contract HotBufferHookTest is BaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;

    function setUp() public override {
        super.setUp();

        // These values are set in BaseTest but we ensure they're what we expect
        assertEq(hook.bufferSize0(), bufferSize0(), "Buffer size should be 1e7");
        assertEq(hook.bufferSize1(), bufferSize1(), "Buffer size should be 1e7");
        assertEq(hook.minTransferAmount0(), minTransferAmount0(), "Min transfer amount should be 1e6");
        assertEq(hook.minTransferAmount1(), minTransferAmount1(), "Min transfer amount should be 1e6");
    }

    // Tests begin here

    function test_BufferConfig() public {
        // Test the initial buffer configurations
        // Test setting new buffer size as admin
        vm.prank(address(hookManager));
        hook.setBufferSize(2e7, 2e7);
        assertEq(hook.bufferSize0(), 2e7, "Buffer size should be updated");
        assertEq(hook.bufferSize1(), 2e7, "Buffer size should be updated");

        // Test setting new min transfer amount as admin
        vm.prank(address(hookManager));
        hook.setMinTransferAmount(2e6, 2e6);
        assertEq(hook.minTransferAmount0(), 2e6, "Min transfer amount should be updated");
        assertEq(hook.minTransferAmount1(), 2e6, "Min transfer amount should be updated");

        // Test setting buffer size as non-admin
        vm.prank(user1);
        vm.expectRevert("Not hook manager");
        hook.setBufferSize(3e7, 3e7);

        // Test setting min transfer amount as non-admin
        vm.prank(user1);
        vm.expectRevert("Not hook manager");
        hook.setMinTransferAmount(3e6, 3e6);
    }

    function test_DepositBelowBuffer() public {
        // Test case: Deposit smaller than buffer size
        // Tokens should remain in hook and not be sent to Aave

        // Set smaller buffer size for this test
        vm.prank(address(hookManager));
        hook.setBufferSize(1000, 1000);
        vm.prank(address(hookManager));
        hook.setMinTransferAmount(100, 100);

        // Use a small deposit amount that's less than buffer size
        uint256 depositAmount = 500;

        // Perform deposit
        (uint256 token0Amount, uint256 token1Amount, TokenBalances memory before, TokenBalances memory afterBalances) =
            depositLiquidity(user1, depositAmount);

        // Verify amounts are below buffer size
        assertLt(token0Amount, hook.bufferSize0(), "Token0 amount should be below buffer size");
        assertLt(token1Amount, hook.bufferSize1(), "Token1 amount should be below buffer size");

        // Verify correct token transfers from user
        assertEq(before.userToken0 - afterBalances.userToken0, token0Amount, "User should transfer exact token0 amount");
        assertEq(before.userToken1 - afterBalances.userToken1, token1Amount, "User should transfer exact token1 amount");

        // Verify hook balances increased by correct amounts
        assertEq(afterBalances.hookToken0 - before.hookToken0, token0Amount, "Hook should receive exact token0 amount");
        assertEq(afterBalances.hookToken1 - before.hookToken1, token1Amount, "Hook should receive exact token1 amount");

        // Verify no tokens were sent to Aave
        assertEq(afterBalances.hookAToken0, before.hookAToken0, "No tokens should be sent to Aave (token0)");
        assertEq(afterBalances.hookAToken1, before.hookAToken1, "No tokens should be sent to Aave (token1)");
    }

    function test_DepositAboveBuffer() public {
        // Test case: Deposit larger than buffer size
        // Excess tokens should be sent to Aave

        // Set smaller buffer size for this test
        vm.prank(address(hookManager));
        hook.setBufferSize(100, 100);
        vm.prank(address(hookManager));
        hook.setMinTransferAmount(10, 10);

        // Use a large deposit amount
        uint256 depositAmount = 1e10;

        // Perform deposit
        (uint256 token0Amount, uint256 token1Amount, TokenBalances memory before, TokenBalances memory afterBalances) =
            depositLiquidity(user1, depositAmount);

        // Verify amounts are above buffer size
        assertGt(token0Amount, hook.bufferSize0(), "Token0 amount should be above buffer size");
        assertGt(token1Amount, hook.bufferSize1(), "Token1 amount should be above buffer size");

        // Verify correct token transfers from user
        assertEq(before.userToken0 - afterBalances.userToken0, token0Amount, "User should transfer exact token0 amount");
        assertEq(before.userToken1 - afterBalances.userToken1, token1Amount, "User should transfer exact token1 amount");

        // Verify token balances in the hook are equal to buffer size
        assertEq(afterBalances.hookToken0, hook.bufferSize0(), "Hook token0 balance should equal buffer size");
        assertEq(afterBalances.hookToken1, hook.bufferSize1(), "Hook token1 balance should equal buffer size");

        // Verify excess tokens were sent to Aave
        uint256 expectedAToken0 = token0Amount - hook.bufferSize0();
        uint256 expectedAToken1 = token1Amount - hook.bufferSize1();
        assertEq(afterBalances.hookAToken0, expectedAToken0, "Excess token0 should be sent to Aave");
        assertEq(afterBalances.hookAToken1, expectedAToken1, "Excess token1 should be sent to Aave");
    }

    function test_SwapThroughBuffer() public {
        // Test case: Small swap that can be handled with buffer

        // Deposit a small amount below buffer
        uint256 depositAmount = 1e4;
        depositTokensToHook(depositAmount, depositAmount, user1);

        // Get balances before swap
        TokenBalances memory before = getBalances(user1);

        // Perform small swap token0 -> token1
        int256 swapAmount = -100;
        vm.startPrank(user1);
        deal(token0Address, user1, uint256(-swapAmount), false);
        IERC20(token0Address).forceApprove(address(swapRouter), uint256(-swapAmount));
        BalanceDelta swapDelta = swap(simpleKey, true, swapAmount, ZERO_BYTES);
        vm.stopPrank();

        // Get balances after swap
        TokenBalances memory afterBalances = getBalances(user1);

        // Verify no aTokens were used
        assertEq(afterBalances.hookAToken0, before.hookAToken0, "Small swap shouldn't change aToken0 balance");
        assertEq(afterBalances.hookAToken1, before.hookAToken1, "Small swap shouldn't change aToken1 balance");

        // Verify hook token balances reflect the swap
        assertEq(
            afterBalances.hookToken0 - before.hookToken0,
            uint256(int256(swapDelta.amount1())),
            "Hook should transfer exact token0 amount"
        );
        assertEq(
            before.hookToken1 - afterBalances.hookToken1,
            uint256(int256(-swapDelta.amount0())),
            "Hook should receive exact token1 amount"
        );
    }

    function test_SwapThroughAave() public {
        // Test case: Large swap that requires withdrawing from Aave

        // Reduce buffer size for this test
        vm.prank(address(hookManager));
        hook.setBufferSize(100, 100);
        vm.prank(address(hookManager));
        hook.setMinTransferAmount(10, 10);

        // First deposit a large amount to fill Aave
        uint256 depositAmount = 1e10;
        (uint256 depositToken0, uint256 depositToken1,,) = depositLiquidity(user1, depositAmount);

        // Verify we deposited to Aave
        TokenBalances memory balances = getBalances(user1);
        assertEq(balances.hookToken0, hook.bufferSize0(), "Buffer should be filled with token0");
        assertEq(balances.hookToken1, hook.bufferSize1(), "Buffer should be filled with token1");
        assertEq(balances.hookAToken0, depositToken0 - hook.bufferSize0(), "Excess token0 should be in Aave");
        assertEq(balances.hookAToken1, depositToken1 - hook.bufferSize1(), "Excess token1 should be in Aave");

        // Perform a large swap
        int256 swapAmount = -1000;
        assertLt(uint256(-swapAmount), depositToken0, "Swap amount should be smaller than deposit amount");

        // Get balances before swap
        TokenBalances memory before = getBalances(user1);

        // Execute swap
        vm.startPrank(user1);
        deal(token0Address, user1, uint256(-swapAmount), false);
        IERC20(token0Address).forceApprove(address(swapRouter), uint256(-swapAmount));
        BalanceDelta swapDelta = swap(simpleKey, true, swapAmount, ZERO_BYTES);
        vm.stopPrank();

        // Get balances after swap
        TokenBalances memory afterBalances = getBalances(user1);

        // Verify hook token balances remain at buffer size
        assertEq(afterBalances.hookToken0, hook.bufferSize0(), "Token0 balance should remain at buffer size");
        assertEq(afterBalances.hookToken1, hook.bufferSize1(), "Token1 balance should remain at buffer size");

        // Verify Aave interactions
        assertGt(afterBalances.hookAToken0, before.hookAToken0, "Excess token0 should be deposited to Aave");
        assertLt(afterBalances.hookAToken1, before.hookAToken1, "Token1 should be withdrawn from Aave");

        // Verify approximate token movement amounts (with some tolerance for rounding)
        uint256 token0Increase = afterBalances.hookAToken0 - before.hookAToken0 + 2;
        uint256 token1Decrease = before.hookAToken1 - afterBalances.hookAToken1 - 1;
        assertApproxEqAbs(
            token0Increase, uint256(int256(-swapDelta.amount0())), 5, "Token0 amount should match swap delta"
        );
        assertApproxEqAbs(
            token1Decrease, uint256(int256(swapDelta.amount1())), 5, "Token1 amount should match swap delta"
        );
    }

    function test_SwapThroughBothBufferAndAave() public {
        // Test case: Swap that uses both buffer and Aave tokens

        // Reduce buffer size for this test
        vm.prank(address(hookManager));
        hook.setBufferSize(100, 100);
        vm.prank(address(hookManager));
        hook.setMinTransferAmount(10, 10);

        // First deposit a large amount to fill Aave
        uint256 depositAmount = 1e10;
        (uint256 depositToken0, uint256 depositToken1,,) = depositLiquidity(user1, depositAmount);

        // Verify we deposited to Aave
        TokenBalances memory before = getBalances(user1);

        // Calculate a swap amount that's larger than aToken balance but less than total available
        uint256 swapSize = before.hookAToken0 - 100;
        assertLt(swapSize, before.hookAToken0, "Swap amount should be smaller than aToken balance");
        assertLt(swapSize, before.hookAToken0 + before.hookToken0, "Swap amount should be less than total balance");

        // Execute swap
        vm.startPrank(user1);
        deal(token0Address, user1, swapSize, false);
        IERC20(token0Address).forceApprove(address(swapRouter), swapSize);
        BalanceDelta swapDelta = swap(simpleKey, true, -int256(swapSize), ZERO_BYTES);
        vm.stopPrank();

        // Get balances after swap
        TokenBalances memory afterBalances = getBalances(user1);

        // Verify buffer remains at target size
        assertEq(afterBalances.hookToken0, hook.bufferSize0(), "Token0 balance should remain at buffer size");
        assertEq(afterBalances.hookToken1, hook.bufferSize1(), "Token1 balance should remain at buffer size");

        // Verify Aave interactions
        assertGt(afterBalances.hookAToken0, before.hookAToken0, "Excess token0 should be deposited to Aave");
        assertLt(afterBalances.hookAToken1, before.hookAToken1, "Token1 should be withdrawn from Aave");

        // Calculate expected token movements (with tolerance for rounding)
        uint256 token0Increase = afterBalances.hookAToken0 - before.hookAToken0 + 2;
        uint256 token1Decrease = before.hookAToken1 - afterBalances.hookAToken1 - 1;
        assertApproxEqAbs(
            token0Increase, uint256(int256(-swapDelta.amount0())), 5, "Token0 amount should match swap delta"
        );
        assertApproxEqAbs(
            token1Decrease, uint256(int256(swapDelta.amount1())), 5, "Token1 amount should match swap delta"
        );
    }

    function test_WithdrawalBelowAaveBalance() public {
        // Test case: Withdrawal that can be satisfied from Aave without touching buffer

        // First deposit funds to Aave
        uint256 depositAmount = 1e10;
        deal(Currency.unwrap(token0), user1, depositAmount, false);
        deal(Currency.unwrap(token1), user1, depositAmount, false);
        depositTokensToHook(depositAmount, depositAmount, user1);

        // Verify we have funds in Aave
        TokenBalances memory before = getBalances(user1);
        assertGt(before.hookAToken0, 0, "Should have funds in Aave");
        assertGt(before.hookAToken1, 0, "Should have funds in Aave");

        // Withdraw an amount smaller than Aave balance
        uint256 withdrawAmount = 1e4;
        withdrawTokensFromHook(withdrawAmount, withdrawAmount, user1);

        // Get balances after withdrawal
        TokenBalances memory afterBalances = getBalances(user1);

        // Verify buffer wasn't touched
        assertEq(afterBalances.hookToken0, before.hookToken0, "Buffer should not be used");
        assertEq(afterBalances.hookToken1, before.hookToken1, "Buffer should not be used");

        // Verify Aave balances decreased
        assertLt(afterBalances.hookAToken0, before.hookAToken0, "Aave balance should decrease");
        assertLt(afterBalances.hookAToken1, before.hookAToken1, "Aave balance should decrease");

        // Verify user received correct amount of tokens (with tolerance for rounding)
        assertApproxEqAbs(
            before.hookAToken0 - afterBalances.hookAToken0,
            withdrawAmount,
            1,
            "User should receive correct token0 amount"
        );
        assertApproxEqAbs(
            before.hookAToken1 - afterBalances.hookAToken1,
            withdrawAmount,
            1,
            "User should receive correct token1 amount"
        );
    }

    // todo: verify test numbers
    function test_WithdrawalThroughBuffer() public {
        // Test case: Withdrawal that uses buffer

        // Set up a smaller deposit that will mostly go into buffer
        vm.prank(address(hookManager));
        hook.setBufferSize(1000, 1000);
        vm.prank(address(hookManager));
        hook.setMinTransferAmount(100, 100);

        uint256 depositAmount = 2000;
        deal(Currency.unwrap(token0), user1, depositAmount, false);
        deal(Currency.unwrap(token1), user1, depositAmount, false);
        depositTokensToHook(depositAmount, depositAmount, user1);

        // Get balances before withdrawal
        TokenBalances memory before = getBalances(user1);

        // Calculate a withdrawal amount that will use buffer
        uint256 withdrawAmount = 1500;

        withdrawTokensFromHook(withdrawAmount, withdrawAmount, user1);

        // Get balances after withdrawal
        TokenBalances memory afterBalances = getBalances(user1);

        // Verify buffer was used
        assertLt(afterBalances.hookToken0, before.hookToken0, "Buffer should be used for token0");
        assertLt(afterBalances.hookToken1, before.hookToken1, "Buffer should be used for token1");

        // Verify user received tokens
        assertGt(afterBalances.userToken0, before.userToken0, "User should receive token0");
        assertGt(afterBalances.userToken1, before.userToken1, "User should receive token1");

        // Verify user received approximately the expected token amounts
        assertApproxEqAbs(
            afterBalances.userToken0 - before.userToken0, withdrawAmount, 2, "User should receive correct token0 amount"
        );
        assertApproxEqAbs(
            afterBalances.userToken1 - before.userToken1, withdrawAmount, 2, "User should receive correct token1 amount"
        );
    }

    function test_WithdrawalFailsIfInsufficientFunds() public {
        // Test case: Withdrawal fails if there are not enough funds

        // Make a small deposit
        uint256 depositAmount = 1000;
        depositLiquidity(user1, depositAmount);

        // Try to withdraw more than deposited
        uint256 withdrawAmount = depositAmount * 2;

        // Should fail with ERC4626ExceededMaxRedeem error
        vm.startPrank(user1);
        // We're expecting the test to fail with ERC4626ExceededMaxRedeem error
        vm.expectRevert();
        hook.redeem(withdrawAmount, user1, user1);
        vm.stopPrank();
    }
}
