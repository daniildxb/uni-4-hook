// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {HookV1Test} from "../HookV1.t.sol";
import {MockERC20} from "../../utils/mocks/MockERC20.sol";
import {MockAToken} from "../../utils/mocks/MockAToken.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";

/**
 * @title YieldAccrualTest
 * @notice Tests the yield accrual functionality of the Aave integration
 * Tests that when Aave generates yield (interest):
 * 1. The hook correctly accounts for the yield
 * 2. The yield increases the value of shares
 * 3. All users' shares appreciate proportionally
 */
contract YieldAccrualTest is HookV1Test {
    using CurrencyLibrary for Currency;

    uint256 oldInitialTokenBalance = 10000;
    uint256 depositAmount = 1000;
    uint256 yieldAmount = 100; // 10% yield

    function setUp() public override {
        super.setUp();

        // Ensure both users have enough tokens for deposits
        deal(Currency.unwrap(token0), user1, oldInitialTokenBalance, false);
        deal(Currency.unwrap(token1), user1, oldInitialTokenBalance, false);
        deal(Currency.unwrap(token0), user2, oldInitialTokenBalance, false);
        deal(Currency.unwrap(token1), user2, oldInitialTokenBalance, false);
    }

    function test_yield_increases_share_value() public {
        // 1. First user deposits into the hook
        vm.startPrank(user1);
        IERC20(Currency.unwrap(token0)).approve(address(hook), depositAmount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), depositAmount);
        (uint256 user1Shares, uint128 user1Liquidity,,) = depositTokensToHook(depositAmount, depositAmount, user1);
        vm.stopPrank();

        // Record initial share value
        uint256 initialShareValue = hook.convertToAssets(user1Shares);

        // 2. Simulate yield accrual by directly minting more aTokens to the hook
        // This simulates interest being earned on the deposited assets
        MockERC20(token0Address).mint(aToken0Address, yieldAmount * 10);
        MockERC20(token1Address).mint(aToken1Address, yieldAmount * 10);

        MockAToken(aToken0Address).mint(address(0), address(hook), yieldAmount);
        MockAToken(aToken1Address).mint(address(0), address(hook), yieldAmount);

        // 3. Check that share value has increased
        uint256 newShareValue = hook.convertToAssets(user1Shares);

        console.log("Initial share value:", initialShareValue);
        console.log("New share value after yield:", newShareValue);
        console.log("Share value increase:", newShareValue - initialShareValue);

        assertGt(newShareValue, initialShareValue, "Share value should increase after yield accrual");

        // 4. Second user deposits the same amount after yield accrual
        vm.startPrank(user2);
        IERC20(Currency.unwrap(token0)).approve(address(hook), depositAmount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), depositAmount);
        (uint256 user2Shares, uint128 user2Liquidity,,) = depositTokensToHook(depositAmount, depositAmount, user2);
        vm.stopPrank();

        // 5. Verify that user2 received fewer shares than user1 for the same token amount
        // because the share price has increased due to yield
        assertLt(user2Shares, user1Shares, "User2 should receive fewer shares for the same deposit after yield accrual");

        // The ratio of shares should reflect the yield accrual
        uint256 expectedUser2Shares = (user1Shares * initialShareValue) / newShareValue;
        assertApproxEqAbs(
            user2Shares, expectedUser2Shares, 1, "User2's shares should be proportional to new share value"
        );

        // 6. Verify both users can redeem their shares for the correct amount of tokens
        // User1 should get their deposit plus a portion of the yield
        vm.startPrank(user1);
        uint256 token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 token1Before = IERC20(token1Address).balanceOf(user1);
        hook.redeem(user1Shares, user1, user1);
        uint256 token0After = IERC20(token0Address).balanceOf(user1);
        uint256 token1After = IERC20(token1Address).balanceOf(user1);
        vm.stopPrank();

        uint256 token0Redeemed = token0After - token0Before;
        uint256 token1Redeemed = token1After - token1Before;

        console.log("User1 token0 redeemed:", token0Redeemed);
        console.log("User1 token1 redeemed:", token1Redeemed);

        // User1 should get back more than they deposited due to yield
        assertGt(token0Redeemed, depositAmount - 5, "User1 should redeem more token0 than deposited");
        assertGt(token1Redeemed, depositAmount - 5, "User1 should redeem more token1 than deposited");

        // User2 redemption
        vm.startPrank(user2);
        token0Before = IERC20(token0Address).balanceOf(user2);
        token1Before = IERC20(token1Address).balanceOf(user2);
        hook.redeem(user2Shares, user2, user2);
        token0After = IERC20(token0Address).balanceOf(user2);
        token1After = IERC20(token1Address).balanceOf(user2);
        vm.stopPrank();

        token0Redeemed = token0After - token0Before;
        token1Redeemed = token1After - token1Before;

        console.log("User2 token0 redeemed:", token0Redeemed);
        console.log("User2 token1 redeemed:", token1Redeemed);

        // User2 should get back approximately what they deposited
        assertApproxEqAbs(token0Redeemed, depositAmount, 5, "User2 should redeem approximately deposited token0 amount");
        assertApproxEqAbs(token1Redeemed, depositAmount, 5, "User2 should redeem approximately deposited token1 amount");
    }

    function test_yield_affects_all_users_equally() public {
        // 1. Both users deposit the same amount initially
        vm.startPrank(user1);
        IERC20(Currency.unwrap(token0)).approve(address(hook), depositAmount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), depositAmount);
        (uint256 user1Shares, uint128 user1Liquidity,,) = depositTokensToHook(depositAmount, depositAmount, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(Currency.unwrap(token0)).approve(address(hook), depositAmount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), depositAmount);
        (uint256 user2Shares, uint128 user2Liquidity,,) = depositTokensToHook(depositAmount, depositAmount, user2);
        vm.stopPrank();

        // Shares should be approximately equal
        assertApproxEqAbs(user1Shares, user2Shares, 1, "Users should receive equal shares for equal deposits");

        // 2. Simulate yield accrual
        MockERC20(token0Address).mint(aToken0Address, yieldAmount * 10);
        MockERC20(token1Address).mint(aToken1Address, yieldAmount * 10);

        MockAToken(aToken0Address).mint(address(0), address(hook), yieldAmount * 2); // double yield for 2 users
        MockAToken(aToken1Address).mint(address(0), address(hook), yieldAmount * 2);

        // 3. Calculate the new value of shares for both users
        uint256 user1ShareValue = hook.convertToAssets(user1Shares);
        uint256 user2ShareValue = hook.convertToAssets(user2Shares);

        console.log("User1 share value after yield:", user1ShareValue);
        console.log("User2 share value after yield:", user2ShareValue);

        // 4. Verify both users' shares appreciated equally
        assertApproxEqAbs(user1ShareValue, user2ShareValue, 1, "Both users' shares should appreciate equally");

        // 5. Verify both users can redeem their shares for the correct amount of tokens
        vm.startPrank(user1);
        uint256 token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 token1Before = IERC20(token1Address).balanceOf(user1);
        hook.redeem(user1Shares, user1, user1);
        uint256 token0After = IERC20(token0Address).balanceOf(user1);
        uint256 token1After = IERC20(token1Address).balanceOf(user1);
        vm.stopPrank();

        uint256 user1Token0Redeemed = token0After - token0Before;
        uint256 user1Token1Redeemed = token1After - token1Before;

        vm.startPrank(user2);
        token0Before = IERC20(token0Address).balanceOf(user2);
        token1Before = IERC20(token1Address).balanceOf(user2);
        hook.redeem(user2Shares, user2, user2);
        token0After = IERC20(token0Address).balanceOf(user2);
        token1After = IERC20(token1Address).balanceOf(user2);
        vm.stopPrank();

        uint256 user2Token0Redeemed = token0After - token0Before;
        uint256 user2Token1Redeemed = token1After - token1Before;

        console.log("User1 token0 redeemed:", user1Token0Redeemed);
        console.log("User1 token1 redeemed:", user1Token1Redeemed);
        console.log("User2 token0 redeemed:", user2Token0Redeemed);
        console.log("User2 token1 redeemed:", user2Token1Redeemed);

        // Both users should redeem approximately the same amount
        assertApproxEqAbs(
            user1Token0Redeemed, user2Token0Redeemed, 2, "Both users should redeem similar token0 amounts"
        );
        assertApproxEqAbs(
            user1Token1Redeemed, user2Token1Redeemed, 2, "Both users should redeem similar token1 amounts"
        );

        // Both users should get more than they deposited due to yield
        assertGt(user1Token0Redeemed, depositAmount - 5, "User1 should redeem more token0 than deposited");
        assertGt(user1Token1Redeemed, depositAmount - 5, "User1 should redeem more token1 than deposited");
        assertGt(user2Token0Redeemed, depositAmount - 5, "User2 should redeem more token0 than deposited");
        assertGt(user2Token1Redeemed, depositAmount - 5, "User2 should redeem more token1 than deposited");
    }

    function test_yield_after_partial_withdrawal() public {
        // 1. First user deposits
        vm.startPrank(user1);
        IERC20(Currency.unwrap(token0)).approve(address(hook), depositAmount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), depositAmount);
        (uint256 user1Shares, uint128 user1Liquidity,,) = depositTokensToHook(depositAmount, depositAmount, user1);
        vm.stopPrank();

        // 2. User withdraws half their shares
        uint256 halfShares = user1Shares / 2;

        vm.startPrank(user1);
        hook.redeem(halfShares, user1, user1);
        vm.stopPrank();

        uint256 remainingShares = IERC20(address(hook)).balanceOf(user1);
        assertApproxEqAbs(remainingShares, user1Shares - halfShares, 1, "User should have half shares remaining");

        // 3. Simulate yield accrual
        MockERC20(token0Address).mint(aToken0Address, yieldAmount * 10);
        MockERC20(token1Address).mint(aToken1Address, yieldAmount * 10);

        MockAToken(aToken0Address).mint(address(0), address(hook), yieldAmount);
        MockAToken(aToken1Address).mint(address(0), address(hook), yieldAmount);

        // 4. Calculate share value after yield
        uint256 shareValueAfterYield = hook.convertToAssets(remainingShares);

        // 5. User withdraws remaining shares
        vm.startPrank(user1);
        uint256 token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 token1Before = IERC20(token1Address).balanceOf(user1);
        hook.redeem(remainingShares, user1, user1);
        uint256 token0After = IERC20(token0Address).balanceOf(user1);
        uint256 token1After = IERC20(token1Address).balanceOf(user1);
        vm.stopPrank();

        uint256 token0Redeemed = token0After - token0Before;
        uint256 token1Redeemed = token1After - token1Before;

        console.log("Final token0 redeemed:", token0Redeemed);
        console.log("Final token1 redeemed:", token1Redeemed);

        // 6. User should get back more than half their deposit due to yield
        assertGt(token0Redeemed, depositAmount / 2, "User should redeem more token0 than half the deposit");
        assertGt(token1Redeemed, depositAmount / 2, "User should redeem more token1 than half the deposit");
    }
}
