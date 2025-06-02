// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ModularHookBaseTest} from "./ModularHookBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";

/**
 * @title ModularHookFeatureComboTest
 * @notice Tests for combined features of ModularHookV1 (allowlist, deposit caps, etc.)
 */
contract ModularHookFeatureComboTest is ModularHookBaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    /**
     * @notice Tests a scenario that combines allowlist and deposit cap features
     * 1. Admin enables allowlist and adds an allowlisted user
     * 2. Admin sets deposit caps
     * 3. Allowlisted user can deposit within caps
     * 4. Non-allowlisted user cannot deposit
     * 5. Allowlisted user cannot exceed deposit caps
     */
    // todo: rewrite the test to use token amounts for deposit instead of specifying actual liquidity value
    function test_allowlist_and_deposit_cap_combined() public {
        // Setup initial state
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        vm.startPrank(initialDepositor);
        hook.redeem(hook.balanceOf(initialDepositor), initialDepositor, initialDepositor);
        vm.stopPrank();

        // Set deposit caps
        uint256 depositCap = 150;
        uint256 allowListedUserShares = 0;
        uint256 nonAllowListedUserShares = 0;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(scaleToken0Amount(depositCap), scaleToken1Amount(depositCap));

        // Enable allowlist and add allowedUser
        ModularHookV1(address(hook)).flipAllowlist();
        ModularHookV1(address(hook)).flipAddressInAllowList(allowedUser);
        vm.stopPrank();

        // Verify settings
        {
            bool isAllowlistEnabled = ModularHookV1(address(hook)).isAllowlistEnabled();
            bool isUserAllowed = ModularHookV1(address(hook)).allowlist(allowedUser);
            uint256 cap0 = ModularHookV1(address(hook)).depositCap0();
            uint256 cap1 = ModularHookV1(address(hook)).depositCap1();

            assertEq(isAllowlistEnabled, true, "Allowlist should be enabled");
            assertEq(isUserAllowed, true, "User should be allowlisted");
            assertEq(cap0, scaleToken0Amount(depositCap), "Deposit cap0 should be set");
            assertEq(cap1, scaleToken1Amount(depositCap), "Deposit cap1 should be set");
        }

        // Test 1: Non-allowlisted user cannot deposit
        uint256 smallDeposit = 50;

        depositTokensToHookExpectRevert(
            scaleToken0Amount(smallDeposit), scaleToken1Amount(smallDeposit), nonAllowedUser
        );

        // Test 2: Allowlisted user can deposit within caps
        (uint256 _allowListedUserShares,,,) =
            depositTokensToHook(scaleToken0Amount(smallDeposit), scaleToken1Amount(smallDeposit), allowedUser);
        allowListedUserShares += _allowListedUserShares;

        // Test 3: Allowlisted user cannot exceed deposit caps
        uint256 largeDeposit = depositCap + 100;
        console.log("large deposit should fail");
        depositTokensToHookExpectRevert(scaleToken0Amount(largeDeposit), scaleToken1Amount(largeDeposit), allowedUser);

        // Test 4: Disabling allowlist should still enforce deposit caps
        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        // Should succeed now that allowlist is disabled, but still under caps
        (uint256 _nonAllowListedUserShares,,,) =
            depositTokensToHook(scaleToken0Amount(smallDeposit), scaleToken1Amount(smallDeposit), nonAllowedUser);
        nonAllowListedUserShares += nonAllowListedUserShares;

        // Test 5: Removing deposit caps but keeping allowlist
        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(0, 0);
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        // Try large deposit with allowlisted user
        (uint256 largeDepositShares,,,) =
            depositTokensToHook(scaleToken0Amount(largeDeposit), scaleToken1Amount(largeDeposit), allowedUser);
        allowListedUserShares += largeDepositShares;
        // Verify large deposit succeeded
        uint256 allowedUserSharesAfterLargeDeposit = ModularHookV1(address(hook)).balanceOf(allowedUser);
        assertEq(
            allowedUserSharesAfterLargeDeposit,
            allowListedUserShares,
            "Allowlisted user's large deposit should succeed when caps are removed"
        );

        // Try large deposit with non-allowlisted user
        console.log("non allowlisted deposit");
        depositTokensToHookExpectRevert(
            scaleToken0Amount(largeDeposit), scaleToken1Amount(largeDeposit), nonAllowedUser
        );
    }

    /**
     * @notice Tests the interaction between deposit caps and withdrawals
     * Verifies that users can withdraw funds even when deposit caps are reached
     */
    function test_withdraw_with_deposit_caps() public {
        // Setup
        vm.startPrank(initialDepositor);
        hook.redeem(hook.balanceOf(initialDepositor), initialDepositor, initialDepositor);
        vm.stopPrank();

        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // Set a low deposit cap
        uint256 depositCap = 20;
        setupDepositCaps(scaleToken0Amount(depositCap), scaleToken1Amount(depositCap));

        // User deposits up to the cap
        (uint256 depositShares,,,) = depositTokensToHook(scaleToken0Amount(depositCap - 1), scaleToken1Amount(depositCap - 1), user1);

        // Verify deposit succeeded
        assertEq(IERC20(address(hook)).balanceOf(user1), depositShares, "Deposit should succeed up to cap");

        // Try to deposit more (should fail)
        depositTokensToHookExpectRevert(scaleToken0Amount(1), scaleToken1Amount(1), user1);

        // User withdraws some funds
        vm.startPrank(user1);
        uint256 partialShares = depositShares / 2;
        hook.redeem(partialShares, user1, user1);
        vm.stopPrank();

        // Check total assets after withdrawal
        uint256 totalAssetsAfterWithdrawal = hook.totalAssets();

        // Verify withdrawal succeeded
        assertEq(
            IERC20(address(hook)).balanceOf(user1), depositShares - partialShares, "Partial withdrawal should succeed"
        );
    }

    /**
     * @notice Tests the interaction between allowlist changes and user deposits/withdrawals
     */
    function test_allowlist_changes_with_active_positions() public {
        // Setup - initially no allowlist
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // Both users deposit
        uint256 depositAmount = 500;
        (uint256 user1Shares,,,) = depositTokensToHook(depositAmount, depositAmount, user1);
        (uint256 user2Shares,,,) = depositTokensToHook(depositAmount, depositAmount, user2);

        // Enable allowlist but only add user1
        setupAllowlist(true, user1);

        // User1 should be able to deposit more
        (uint256 additionalUser1Shares,,,) = depositTokensToHook(depositAmount, depositAmount, user1);
        assertGt(additionalUser1Shares, 0, "Allowlisted user should be able to deposit more");

        // User2 should not be able to deposit more
        depositTokensToHookExpectRevert(depositAmount, depositAmount, user2);

        // Both users should be able to withdraw their existing funds
        vm.startPrank(user1);
        hook.redeem(user1Shares + additionalUser1Shares, user1, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        hook.redeem(user2Shares, user2, user2);
        vm.stopPrank();

        // Verify withdrawals succeeded
        assertEq(IERC20(address(hook)).balanceOf(user1), 0, "User1 should be able to withdraw all funds");
        assertEq(IERC20(address(hook)).balanceOf(user2), 0, "User2 should be able to withdraw all funds");
    }
}
