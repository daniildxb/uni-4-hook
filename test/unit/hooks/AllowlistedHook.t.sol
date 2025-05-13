// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseTest} from "../../BaseTest.sol";
import {ModularHookV1} from "../../../src/ModularHookV1.sol";

contract AllowlistedHookTest is BaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // Test users
    address public allowedUser = address(777);
    address public nonAllowedUser = address(888);

    function setUp() public override {
        super.setUp();

        // Give tokens to test users
        deal(Currency.unwrap(token0), allowedUser, initialTokenBalance, false);
        deal(Currency.unwrap(token1), allowedUser, initialTokenBalance, false);
        deal(Currency.unwrap(token0), nonAllowedUser, initialTokenBalance, false);
        deal(Currency.unwrap(token1), nonAllowedUser, initialTokenBalance, false);
    }

    function test_allowlist_disabled_by_default() public {
        // Check that allowlisting is disabled by default
        bool isAllowlistEnabled = ModularHookV1(address(hook)).isAllowlistEnabled();
        assertEq(isAllowlistEnabled, false, "Allowlist should be disabled by default");

        // Deposit should succeed for non-allowlisted user when feature is disabled
        uint256 depositAmount = 1000;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        vm.startPrank(nonAllowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should not revert since allowlist is disabled
        hook.deposit(depositAmount, nonAllowedUser);
        vm.stopPrank();

        // Verify deposit was successful
        uint256 userShares = ModularHookV1(address(hook)).balanceOf(nonAllowedUser);
        assertEq(userShares, depositAmount, "Non-allowlisted user should be able to deposit when allowlist is disabled");
    }

    function test_enable_allowlist() public {
        // Enable allowlist as admin
        vm.startPrank(admin);
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        // Verify allowlist is enabled
        bool isAllowlistEnabled = ModularHookV1(address(hook)).isAllowlistEnabled();
        assertEq(isAllowlistEnabled, true, "Allowlist should be enabled");
    }

    function test_add_to_allowlist() public {
        // Enable allowlist and add allowedUser to it
        vm.startPrank(admin);
        ModularHookV1(address(hook)).flipAllowlist();
        ModularHookV1(address(hook)).flipAddressInAllowList(allowedUser);
        vm.stopPrank();

        // Verify user is allowlisted
        bool isAllowed = ModularHookV1(address(hook)).allowlist(allowedUser);
        assertEq(isAllowed, true, "User should be allowlisted");
    }

    function test_deposit_rejected_for_non_allowlisted() public {
        // Enable allowlist
        vm.startPrank(admin);
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        // Try to deposit as non-allowlisted user
        uint256 depositAmount = 1000;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        vm.startPrank(nonAllowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should revert with "Not allowed"
        vm.expectRevert("Not allowed");
        hook.deposit(depositAmount, nonAllowedUser);
        vm.stopPrank();
    }

    function test_deposit_accepted_for_allowlisted() public {
        // Enable allowlist and add allowedUser
        vm.startPrank(admin);
        ModularHookV1(address(hook)).flipAllowlist();
        ModularHookV1(address(hook)).flipAddressInAllowList(allowedUser);
        vm.stopPrank();

        // Deposit as allowlisted user
        uint256 depositAmount = 1000;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        vm.startPrank(allowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should not revert since user is allowlisted
        hook.deposit(depositAmount, allowedUser);
        vm.stopPrank();

        // Verify deposit was successful
        uint256 userShares = ModularHookV1(address(hook)).balanceOf(allowedUser);
        assertEq(userShares, depositAmount, "Allowlisted user should be able to deposit");
    }

    function test_remove_from_allowlist() public {
        // Enable allowlist and add allowedUser
        vm.startPrank(admin);
        ModularHookV1(address(hook)).flipAllowlist();
        ModularHookV1(address(hook)).flipAddressInAllowList(allowedUser);

        // Verify user is allowlisted
        bool isAllowed = ModularHookV1(address(hook)).allowlist(allowedUser);
        assertEq(isAllowed, true, "User should be allowlisted");

        // Remove user from allowlist
        ModularHookV1(address(hook)).flipAddressInAllowList(allowedUser);
        vm.stopPrank();

        // Verify user is no longer allowlisted
        isAllowed = ModularHookV1(address(hook)).allowlist(allowedUser);
        assertEq(isAllowed, false, "User should no longer be allowlisted");

        // Try to deposit as now non-allowlisted user
        uint256 depositAmount = 1000;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        vm.startPrank(allowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should revert with "Not allowed"
        vm.expectRevert("Not allowed");
        hook.deposit(depositAmount, allowedUser);
        vm.stopPrank();
    }

    function test_disable_allowlist() public {
        // First enable allowlist
        vm.startPrank(admin);
        ModularHookV1(address(hook)).flipAllowlist();

        // Verify allowlist is enabled
        bool isAllowlistEnabled = ModularHookV1(address(hook)).isAllowlistEnabled();
        assertEq(isAllowlistEnabled, true, "Allowlist should be enabled");

        // Disable allowlist
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        // Verify allowlist is disabled
        isAllowlistEnabled = ModularHookV1(address(hook)).isAllowlistEnabled();
        assertEq(isAllowlistEnabled, false, "Allowlist should be disabled");

        // Deposit should succeed for non-allowlisted user when feature is disabled
        uint256 depositAmount = 1000;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        vm.startPrank(nonAllowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should not revert since allowlist is disabled
        hook.deposit(depositAmount, nonAllowedUser);
        vm.stopPrank();

        // Verify deposit was successful
        uint256 userShares = ModularHookV1(address(hook)).balanceOf(nonAllowedUser);
        assertEq(userShares, depositAmount, "Non-allowlisted user should be able to deposit when allowlist is disabled");
    }

    function test_only_admin_can_manage_allowlist() public {
        // Try to flip allowlist as non-admin
        vm.startPrank(nonAllowedUser);
        vm.expectRevert("Not admin");
        ModularHookV1(address(hook)).flipAllowlist();

        // Try to add to allowlist as non-admin
        vm.expectRevert("Not admin");
        ModularHookV1(address(hook)).flipAddressInAllowList(allowedUser);
        vm.stopPrank();
    }
}
