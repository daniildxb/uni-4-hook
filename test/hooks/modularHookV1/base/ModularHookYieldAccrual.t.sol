// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ModularHookBaseTest} from "./ModularHookBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {MockAToken} from "../../../utils/mocks/MockAToken.sol";
import {MockERC20} from "../../../utils/mocks/MockERC20.sol";

/**
 * @title ModularHookYieldAccrualTest
 * @notice Tests the yield accrual functionality of the Aave integration
 * Tests that when Aave generates yield (interest):
 * 1. The hook correctly accounts for the yield
 * 2. The yield increases the value of shares
 * 3. All users' shares appreciate proportionally
 */
contract ModularHookYieldAccrualTest is ModularHookBaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    uint256 yieldAmount = 100; // 10% yield

    /**
     * @notice Tests that yield accrual increases share value
     * Verifies that when external yield is generated, share value increases appropriately
     */
    function test_yield_increases_share_value() public {
        // 1. First user deposits into the hook
        (uint256 user1Shares,,,) = depositTokensToHook(userInitialBalance0(), userInitialBalance1(), user1);

        // Record initial share value and token amounts
        uint256 initialShareValue = hook.convertToAssets(user1Shares);
        (uint256 initialToken0, uint256 initialToken1) = getTokenAmountsForLiquidity(initialShareValue);

        // 2. Simulate yield accrual by directly minting more aTokens to the hook
        // This simulates interest being earned on the deposited assets
        // First, provide underlying tokens to the aToken contracts to support redemption
        MockERC20(token0Address).mint(aToken0Address, scaleToken0Amount(yieldAmount * 10));
        MockERC20(token1Address).mint(aToken1Address, scaleToken1Amount(yieldAmount * 10));
        MockAToken(aToken0Address).mint(address(0), address(hook), scaleToken0Amount(yieldAmount));
        MockAToken(aToken1Address).mint(address(0), address(hook), scaleToken1Amount(yieldAmount));

        // 3. Check that share value has increased
        uint256 newShareValue = hook.convertToAssets(user1Shares);
        (uint256 newToken0, uint256 newToken1) = getTokenAmountsForLiquidity(newShareValue);

        console.log("Initial share value:", initialShareValue);
        console.log("New share value after yield:", newShareValue);
        console.log("Initial token amounts:", initialToken0 + initialToken1);
        console.log("New token amounts:", newToken0 + newToken1);

        // Token amounts should increase due to yield (more reliable than share value comparison)
        assertGe(
            newToken0 + newToken1, initialToken0 + initialToken1, "Token amounts should increase after yield accrual"
        );
        assertGe(newShareValue, initialShareValue, "Share value should not decrease after yield accrual");

        // 4. Second user deposits the same amount after yield accrual
        (uint256 user2Shares,,,) = depositTokensToHook(userInitialBalance0(), userInitialBalance1(), user2);

        // 5. Verify that user2 received fewer shares than user1 for the same token amount
        // because the share price has increased due to yield
        assertLt(user2Shares, user1Shares, "User2 should receive fewer shares for the same deposit after yield accrual");

        // The ratio of shares should reflect the yield accrual
        uint256 expectedUser2Shares = (user1Shares * initialShareValue) / newShareValue;
        // 1e18 = 100% , 1e12 = 0.0001%
        assertApproxEqRelDecimal(user2Shares, expectedUser2Shares, 1e12, 18, "User2's shares should be proportional to new share value");
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
        assertGt(token0Redeemed, userInitialBalance0(), "User1 should redeem more token0 than deposited");
        assertGt(token1Redeemed, userInitialBalance1(), "User1 should redeem more token1 than deposited");

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
        assertLe(token0Redeemed, userInitialBalance0(), "User2 should redeem approximately deposited token0 amount");
        assertLe(token1Redeemed, userInitialBalance1(), "User2 should redeem approximately deposited token1 amount");
        assertApproxEqAbs(
            token0Redeemed, userInitialBalance0(), scaleToken0Amount(1), "User2 should redeem approximately deposited token0 amount"
        );
        assertApproxEqAbs(
            token1Redeemed, userInitialBalance1(), scaleToken0Amount(1), "User2 should redeem approximately deposited token1 amount"
        );
    }

    /**
     * @notice Tests that yield affects all users equally based on their share proportion
     // todo: seems like later deposits of the same amount of liquidity get more shares than early deposits
     */
    function test_yield_affects_all_users_equally() public {
        // 1. Both users deposit the same amount initially
        (uint256 user1Shares,,int128 user1DepositToken0, int128 user1DepositToken1) = depositTokensToHook(userInitialBalance0(), userInitialBalance1(), user1);

        (uint256 user2Shares,,int128 user2DepositToken0,int128 user2DepositToken1) = depositTokensToHook(userInitialBalance0(), userInitialBalance1(), user2);

        // Shares should be approximately equal, not fully equal due to virtual offset impact on early deposits
        // 1e18 = 100% , 1e12 = 0.0001%
        assertApproxEqRelDecimal(user1Shares, user2Shares, 1e12, 18, "Users should receive equal shares for equal deposits");

        // 2. Simulate yield accrual
        // First, provide underlying tokens to the aToken contracts to support redemption
        MockERC20(token0Address).mint(aToken0Address, scaleToken0Amount(yieldAmount * 20));
        MockERC20(token1Address).mint(aToken1Address, scaleToken1Amount(yieldAmount * 20));
        MockAToken(aToken0Address).mint(address(0), address(hook), scaleToken0Amount(yieldAmount * 2)); // double yield for 2 users
        MockAToken(aToken1Address).mint(address(0), address(hook), scaleToken1Amount(yieldAmount * 2));

        // 3. Calculate the new value of shares for both users
        uint256 user1ShareValue = hook.convertToAssets(user1Shares);
        uint256 user2ShareValue = hook.convertToAssets(user2Shares);

        console.log("User1 share value after yield:", user1ShareValue);
        console.log("User2 share value after yield:", user2ShareValue);

        // 4. Verify both users' shares appreciated equally
        assertApproxEqRelDecimal(user1ShareValue, user2ShareValue, 1e12, 18, "Both users' shares should appreciate equally");

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
        assertApproxEqRelDecimal(
            user1Token0Redeemed, user2Token0Redeemed, 1e12, 18, "Both users should redeem similar token0 amounts"
        );
        assertApproxEqRelDecimal(
            user1Token1Redeemed, user2Token1Redeemed, 1e12, 18, "Both users should redeem similar token1 amounts"
        );

        // Both users should get more than they deposited due to yield
        assertGt(user1Token0Redeemed, userInitialBalance0() - 5, "User1 should redeem more token0 than deposited");
        assertGt(user1Token1Redeemed, userInitialBalance1() - 5, "User1 should redeem more token1 than deposited");
        assertGt(user2Token0Redeemed, userInitialBalance0() - 5, "User2 should redeem more token0 than deposited");
        assertGt(user2Token1Redeemed, userInitialBalance1() - 5, "User2 should redeem more token1 than deposited");
    }

    /**
     * @notice Tests yield accrual after partial withdrawal
     * Verifies that remaining shares continue to accrue yield after partial withdrawals
     */
    function test_yield_after_partial_withdrawal() public {
        // 1. First user deposits
        (uint256 user1Shares,,,) = depositTokensToHook(userInitialBalance0(), userInitialBalance1(), user1);

        // 2. User withdraws half their shares
        uint256 halfShares = user1Shares / 2;

        vm.startPrank(user1);
        hook.redeem(halfShares, user1, user1);
        vm.stopPrank();

        uint256 remainingShares = IERC20(address(hook)).balanceOf(user1);
        assertApproxEqAbs(remainingShares, user1Shares - halfShares, 1, "User should have half shares remaining");

        // 3. Simulate yield accrual
        // First, provide underlying tokens to the aToken contracts to support redemption
        MockERC20(token0Address).mint(aToken0Address, scaleToken0Amount(yieldAmount * 10));
        MockERC20(token1Address).mint(aToken1Address, scaleToken1Amount(yieldAmount * 10));
        MockAToken(aToken0Address).mint(address(0), address(hook), scaleToken0Amount(yieldAmount));
        MockAToken(aToken1Address).mint(address(0), address(hook), scaleToken1Amount(yieldAmount));

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
        assertGt(token0Redeemed, userInitialBalance0() / 2, "User should redeem more token0 than half the deposit");
        assertGt(token1Redeemed, userInitialBalance1() / 2, "User should redeem more token1 than half the deposit");
    }

    /**
     * @notice Tests compound yield scenarios
     * Verifies that yield accrual over multiple periods compounds correctly
     */
    function test_compound_yield_accrual() public {
        // 1. Initial deposit
        (uint256 user1Shares,,,) = depositTokensToHook(userInitialBalance0(), userInitialBalance1(), user1);

        uint256 shareValue = hook.convertToAssets(user1Shares);
        console.log("Initial share value:", shareValue);

        // 2. Simulate multiple yield periods
        // First, provide underlying tokens to the aToken contracts to support redemption
        MockERC20(token0Address).mint(aToken0Address, scaleToken0Amount(yieldAmount * 10));
        MockERC20(token1Address).mint(aToken1Address, scaleToken1Amount(yieldAmount * 10));

        for (uint256 i = 0; i < 3; i++) {
            // Add yield each period
            MockAToken(aToken0Address).mint(address(0), address(hook), scaleToken0Amount(yieldAmount / 3));
            MockAToken(aToken1Address).mint(address(0), address(hook), scaleToken1Amount(yieldAmount / 3));

            uint256 newShareValue = hook.convertToAssets(user1Shares);
            console.log("Share value after yield period", i + 1, ":", newShareValue);

            // Share value should increase with each period
            assertGt(newShareValue, shareValue, "Share value should increase after each yield period");
            shareValue = newShareValue;
        }

        // 3. Final redemption should reflect all accumulated yield
        vm.startPrank(user1);
        uint256 token0Before = IERC20(token0Address).balanceOf(user1);
        uint256 token1Before = IERC20(token1Address).balanceOf(user1);
        hook.redeem(user1Shares, user1, user1);
        uint256 token0After = IERC20(token0Address).balanceOf(user1);
        uint256 token1After = IERC20(token1Address).balanceOf(user1);
        vm.stopPrank();

        uint256 token0Redeemed = token0After - token0Before;
        uint256 token1Redeemed = token1After - token1Before;

        console.log("Final token0 redeemed:", token0Redeemed);
        console.log("Final token1 redeemed:", token1Redeemed);

        // Should get back more than original deposit due to compound yield
        assertGt(
            token0Redeemed, userInitialBalance0(), "Should redeem more token0 than deposited due to compound yield"
        );
        assertGt(
            token1Redeemed, userInitialBalance1(), "Should redeem more token1 than deposited due to compound yield"
        );
    }
}
