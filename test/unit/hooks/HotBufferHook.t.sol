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

    // Test accounts
    address public adminAddress = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);
    address public user = address(0xABCD);
    uint256 initialTokenBalance = 10000;

    // Common variables
    address token0Address;
    address token1Address;
    address aToken0Address;
    address aToken1Address;

    // Test state
    struct TokenBalances {
        uint256 userToken0;
        uint256 userToken1;
        uint256 hookToken0;
        uint256 hookToken1;
        uint256 hookAToken0;
        uint256 hookAToken1;
    }

    function setUp() public override {
        super.setUp();

        // Fund the user
        vm.deal(user, 100 ether);

        // Give tokens to the pool manager
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // Give tokens to the user
        deal(Currency.unwrap(token0), user, initialTokenBalance, false);
        deal(Currency.unwrap(token1), user, initialTokenBalance, false);

        // Store commonly used addresses
        token0Address = Currency.unwrap(token0);
        token1Address = Currency.unwrap(token1);
        aToken0Address = hook.aToken0();
        aToken1Address = hook.aToken1();

        // These values are set in BaseTest but we ensure they're what we expect
        assertEq(hook.bufferSize(), 1e7, "Buffer size should be 1e7");
        assertEq(hook.minTransferAmount(), 1e6, "Min transfer amount should be 1e6");
    }

    // Helper function to get current token balances
    function getBalances() internal view returns (TokenBalances memory balances) {
        balances.userToken0 = IERC20(token0Address).balanceOf(user);
        balances.userToken1 = IERC20(token1Address).balanceOf(user);
        balances.hookToken0 = IERC20(token0Address).balanceOf(address(hook));
        balances.hookToken1 = IERC20(token1Address).balanceOf(address(hook));
        balances.hookAToken0 = IERC20(aToken0Address).balanceOf(address(hook));
        balances.hookAToken1 = IERC20(aToken1Address).balanceOf(address(hook));
    }

    // Helper function to get token amounts for a liquidity amount
    function getTokenAmountsForLiquidity(uint256 liquidity)
        internal
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        (int128 token0Delta, int128 token1Delta) = hook.getTokenAmountsForLiquidity(liquidity);
        token0Amount = token0Delta < 0 ? uint256(uint128(-token0Delta)) : 0;
        token1Amount = token1Delta < 0 ? uint256(uint128(-token1Delta)) : 0;
    }

    // Helper function to deposit liquidity
    function depositLiquidity(uint256 depositAmount)
        internal
        returns (
            uint256 token0Amount,
            uint256 token1Amount,
            TokenBalances memory before,
            TokenBalances memory afterBalances
        )
    {
        // Get token amounts for this liquidity
        (token0Amount, token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        // Make sure user has enough tokens
        deal(token0Address, user, token0Amount, false);
        deal(token1Address, user, token1Amount, false);

        // Approve tokens
        vm.startPrank(user);
        IERC20(token0Address).approve(address(hook), token0Amount);
        IERC20(token1Address).approve(address(hook), token1Amount);

        // Get balances before deposit
        before = getBalances();

        // Deposit liquidity
        hook.deposit(depositAmount, user);
        vm.stopPrank();

        // Get balances after deposit
        afterBalances = getBalances();
    }

    // Tests begin here

    function test_BufferConfig() public {
        // Test the initial buffer configurations
        assertEq(hook.bufferSize(), 1e7, "Buffer size should be set correctly");
        assertEq(hook.minTransferAmount(), 1e6, "Min transfer amount should be set correctly");

        // Test setting new buffer size as admin
        vm.prank(adminAddress);
        hook.setBufferSize(2e7);
        assertEq(hook.bufferSize(), 2e7, "Buffer size should be updated");

        // Test setting new min transfer amount as admin
        vm.prank(adminAddress);
        hook.setMinTransferAmount(2e6);
        assertEq(hook.minTransferAmount(), 2e6, "Min transfer amount should be updated");

        // Test setting buffer size as non-admin
        vm.prank(user);
        vm.expectRevert("Not owner");
        hook.setBufferSize(3e7);

        // Test setting min transfer amount as non-admin
        vm.prank(user);
        vm.expectRevert("Not owner");
        hook.setMinTransferAmount(3e6);
    }

    function test_DepositBelowBuffer() public {
        // Test case: Deposit smaller than buffer size
        // Tokens should remain in hook and not be sent to Aave

        // Set smaller buffer size for this test
        vm.prank(adminAddress);
        hook.setBufferSize(1000);
        vm.prank(adminAddress);
        hook.setMinTransferAmount(100);

        // Use a small deposit amount that's less than buffer size
        uint256 depositAmount = 500;

        // Perform deposit
        (uint256 token0Amount, uint256 token1Amount, TokenBalances memory before, TokenBalances memory afterBalances) =
            depositLiquidity(depositAmount);

        // Verify amounts are below buffer size
        assertLt(token0Amount, hook.bufferSize(), "Token0 amount should be below buffer size");
        assertLt(token1Amount, hook.bufferSize(), "Token1 amount should be below buffer size");

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
        vm.prank(adminAddress);
        hook.setBufferSize(100);
        vm.prank(adminAddress);
        hook.setMinTransferAmount(10);

        // Use a large deposit amount
        uint256 depositAmount = 1e10;

        // Perform deposit
        (uint256 token0Amount, uint256 token1Amount, TokenBalances memory before, TokenBalances memory afterBalances) =
            depositLiquidity(depositAmount);

        // Verify amounts are above buffer size
        assertGt(token0Amount, hook.bufferSize(), "Token0 amount should be above buffer size");
        assertGt(token1Amount, hook.bufferSize(), "Token1 amount should be above buffer size");

        // Verify correct token transfers from user
        assertEq(before.userToken0 - afterBalances.userToken0, token0Amount, "User should transfer exact token0 amount");
        assertEq(before.userToken1 - afterBalances.userToken1, token1Amount, "User should transfer exact token1 amount");

        // Verify token balances in the hook are equal to buffer size
        assertEq(afterBalances.hookToken0, hook.bufferSize(), "Hook token0 balance should equal buffer size");
        assertEq(afterBalances.hookToken1, hook.bufferSize(), "Hook token1 balance should equal buffer size");

        // Verify excess tokens were sent to Aave
        uint256 expectedAToken0 = token0Amount - hook.bufferSize();
        uint256 expectedAToken1 = token1Amount - hook.bufferSize();
        assertEq(afterBalances.hookAToken0, expectedAToken0, "Excess token0 should be sent to Aave");
        assertEq(afterBalances.hookAToken1, expectedAToken1, "Excess token1 should be sent to Aave");
    }

    function test_SwapThroughBuffer() public {
        // Test case: Small swap that can be handled with buffer

        // Deposit a small amount below buffer
        uint256 depositAmount = 1e4;
        (uint256 depositToken0, uint256 depositToken1,, TokenBalances memory afterBal) = depositLiquidity(depositAmount);

        // Verify deposit was below buffer size
        assertLt(depositToken0, hook.bufferSize(), "Deposit amount should be below buffer size");
        assertLt(depositToken1, hook.bufferSize(), "Deposit amount should be below buffer size");

        // Get balances before swap
        TokenBalances memory before = getBalances();

        // Perform small swap token0 -> token1
        int256 swapAmount = -100;
        vm.startPrank(user);
        deal(token0Address, user, uint256(-swapAmount), false);
        IERC20(token0Address).forceApprove(address(swapRouter), uint256(-swapAmount));
        BalanceDelta swapDelta = swap(simpleKey, true, swapAmount, ZERO_BYTES);
        vm.stopPrank();

        // Get balances after swap
        TokenBalances memory afterBalances = getBalances();

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
            before.hookToken1 - afterBalances.hookToken1 + 1,
            uint256(int256(-swapDelta.amount0())),
            "Hook should receive exact token1 amount"
        );
    }

    function test_SwapThroughAave() public {
        // Test case: Large swap that requires withdrawing from Aave

        // Reduce buffer size for this test
        vm.prank(adminAddress);
        hook.setBufferSize(100);
        vm.prank(adminAddress);
        hook.setMinTransferAmount(10);

        // First deposit a large amount to fill Aave
        uint256 depositAmount = 1e10;
        (uint256 depositToken0, uint256 depositToken1,, TokenBalances memory afterBal) = depositLiquidity(depositAmount);

        // Verify we deposited to Aave
        TokenBalances memory balances = getBalances();
        assertEq(balances.hookToken0, hook.bufferSize(), "Buffer should be filled with token0");
        assertEq(balances.hookToken1, hook.bufferSize(), "Buffer should be filled with token1");
        assertEq(balances.hookAToken0, depositToken0 - hook.bufferSize(), "Excess token0 should be in Aave");
        assertEq(balances.hookAToken1, depositToken1 - hook.bufferSize(), "Excess token1 should be in Aave");

        // Perform a large swap
        int256 swapAmount = -1000;
        assertLt(uint256(-swapAmount), depositToken0, "Swap amount should be smaller than deposit amount");

        // Get balances before swap
        TokenBalances memory before = getBalances();

        // Execute swap
        vm.startPrank(user);
        deal(token0Address, user, uint256(-swapAmount), false);
        IERC20(token0Address).forceApprove(address(swapRouter), uint256(-swapAmount));
        BalanceDelta swapDelta = swap(simpleKey, true, swapAmount, ZERO_BYTES);
        vm.stopPrank();

        // Get balances after swap
        TokenBalances memory afterBalances = getBalances();

        // Verify hook token balances remain at buffer size
        assertEq(afterBalances.hookToken0, hook.bufferSize(), "Token0 balance should remain at buffer size");
        assertEq(afterBalances.hookToken1, hook.bufferSize(), "Token1 balance should remain at buffer size");

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
        vm.prank(adminAddress);
        hook.setBufferSize(100);
        vm.prank(adminAddress);
        hook.setMinTransferAmount(10);

        // First deposit a large amount to fill Aave
        uint256 depositAmount = 1e10;
        (uint256 depositToken0, uint256 depositToken1,, TokenBalances memory afterBal) = depositLiquidity(depositAmount);

        // Verify we deposited to Aave
        TokenBalances memory before = getBalances();

        // Calculate a swap amount that's larger than aToken balance but less than total available
        uint256 swapSize = before.hookAToken0 - 100;
        assertLt(swapSize, before.hookAToken0, "Swap amount should be smaller than aToken balance");
        assertLt(swapSize, before.hookAToken0 + before.hookToken0, "Swap amount should be less than total balance");

        // Execute swap
        vm.startPrank(user);
        deal(token0Address, user, swapSize, false);
        IERC20(token0Address).forceApprove(address(swapRouter), swapSize);
        BalanceDelta swapDelta = swap(simpleKey, true, -int256(swapSize), ZERO_BYTES);
        vm.stopPrank();

        // Get balances after swap
        TokenBalances memory afterBalances = getBalances();

        // Verify buffer remains at target size
        assertEq(afterBalances.hookToken0, hook.bufferSize(), "Token0 balance should remain at buffer size");
        assertEq(afterBalances.hookToken1, hook.bufferSize(), "Token1 balance should remain at buffer size");

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
        (uint256 depositToken0, uint256 depositToken1,, TokenBalances memory afterBal) = depositLiquidity(depositAmount);

        // Verify we have funds in Aave
        TokenBalances memory before = getBalances();
        assertGt(before.hookAToken0, 0, "Should have funds in Aave");
        assertGt(before.hookAToken1, 0, "Should have funds in Aave");

        // Withdraw an amount smaller than Aave balance
        uint256 withdrawAmount = 1e4;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(withdrawAmount);

        // Verify withdrawal amount is smaller than Aave balance
        assertLt(token0Amount, before.hookAToken0, "Withdrawal amount should be less than Aave balance");
        assertLt(token1Amount, before.hookAToken1, "Withdrawal amount should be less than Aave balance");

        // Execute withdrawal
        vm.startPrank(user);
        hook.redeem(withdrawAmount, user, user);
        vm.stopPrank();

        // Get balances after withdrawal
        TokenBalances memory afterBalances = getBalances();

        // Verify buffer wasn't touched
        assertEq(afterBalances.hookToken0, before.hookToken0, "Buffer should not be used");
        assertEq(afterBalances.hookToken1, before.hookToken1, "Buffer should not be used");

        // Verify Aave balances decreased
        assertLt(afterBalances.hookAToken0, before.hookAToken0, "Aave balance should decrease");
        assertLt(afterBalances.hookAToken1, before.hookAToken1, "Aave balance should decrease");

        // Verify user received correct amount of tokens (with tolerance for rounding)
        assertApproxEqAbs(
            before.hookAToken0 - afterBalances.hookAToken0, token0Amount, 1, "User should receive correct token0 amount"
        );
        assertApproxEqAbs(
            before.hookAToken1 - afterBalances.hookAToken1, token1Amount, 1, "User should receive correct token1 amount"
        );
    }


    // todo: verify test numbers
    function test_WithdrawalThroughBuffer() public {
        // Test case: Withdrawal that uses buffer

        // Set up a smaller deposit that will mostly go into buffer
        vm.prank(adminAddress);
        hook.setBufferSize(1000);
        vm.prank(adminAddress);
        hook.setMinTransferAmount(100);

        uint256 depositAmount = 2000;
        (uint256 depositToken0, uint256 depositToken1,, TokenBalances memory afterBal) = depositLiquidity(depositAmount);

        // Get balances before withdrawal
        TokenBalances memory before = getBalances();

        // Calculate a withdrawal amount that will use buffer
        uint256 withdrawAmount = depositAmount / 2;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(withdrawAmount);

        // Execute withdrawal
        vm.startPrank(user);
        hook.redeem(withdrawAmount, user, user);
        vm.stopPrank();

        // Get balances after withdrawal
        TokenBalances memory afterBalances = getBalances();

        // Verify buffer was used
        assertLt(afterBalances.hookToken0, before.hookToken0, "Buffer should be used for token0");
        assertLt(afterBalances.hookToken1, before.hookToken1, "Buffer should be used for token1");

        // Verify user received tokens
        assertGt(afterBalances.userToken0, before.userToken0, "User should receive token0");
        assertGt(afterBalances.userToken1, before.userToken1, "User should receive token1");

        // Verify user received approximately the expected token amounts
        assertApproxEqAbs(
            afterBalances.userToken0 - before.userToken0, token0Amount, 2, "User should receive correct token0 amount"
        );
        assertApproxEqAbs(
            afterBalances.userToken1 - before.userToken1, token1Amount, 2, "User should receive correct token1 amount"
        );
    }

    function test_WithdrawalFailsIfInsufficientFunds() public {
        // Test case: Withdrawal fails if there are not enough funds

        // Make a small deposit
        uint256 depositAmount = 1000;
        depositLiquidity(depositAmount);

        // Try to withdraw more than deposited
        uint256 withdrawAmount = depositAmount * 2;

        // Should fail with ERC4626ExceededMaxRedeem error
        vm.startPrank(user);
        // We're expecting the test to fail with ERC4626ExceededMaxRedeem error
        vm.expectRevert();
        hook.redeem(withdrawAmount, user, user);
        vm.stopPrank();
    }
}
