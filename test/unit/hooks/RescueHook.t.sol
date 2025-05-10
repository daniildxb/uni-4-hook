// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {RescueHook} from "../../../src/hooks/RescueHook.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Test for the rescue hook functionality
 */
contract RescueHookTest is BaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // Addresses for testing
    address public adminAddress = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);
    address public nonAdminUser = address(0xABCD);
    address public anotherUser = address(0xDCBA);

    function setUp() public override {
        super.setUp();

        // Fund non-admin users
        vm.deal(nonAdminUser, 100 ether);
        vm.deal(anotherUser, 100 ether);

        // Give some tokens to the hook directly (simulating tokens being stuck)
        deal(Currency.unwrap(token0), address(hook), 1000, false);
    }

    function test_RescueAsAdmin() public {
        // Setup
        uint256 rescueAmount = 500;
        address tokenAddress = Currency.unwrap(token0);
        uint256 hookBalanceBefore = IERC20(tokenAddress).balanceOf(address(hook));
        uint256 adminBalanceBefore = IERC20(tokenAddress).balanceOf(adminAddress);

        // Act as admin
        vm.prank(adminAddress);

        // Rescue tokens
        vm.expectEmit(true, true, true, true);
        emit RescueHook.ERC20Rescued(adminAddress, tokenAddress, rescueAmount);
        hook.rescue(tokenAddress, rescueAmount);

        // Verify balances changed correctly
        uint256 hookBalanceAfter = IERC20(tokenAddress).balanceOf(address(hook));
        uint256 adminBalanceAfter = IERC20(tokenAddress).balanceOf(adminAddress);

        assertEq(hookBalanceAfter, hookBalanceBefore - rescueAmount, "Hook balance should decrease by rescue amount");
        assertEq(adminBalanceAfter, adminBalanceBefore + rescueAmount, "Admin balance should increase by rescue amount");
    }

    function test_RescueAsNonAdmin() public {
        // Setup
        uint256 rescueAmount = 500;
        address tokenAddress = Currency.unwrap(token0);

        // Act as non-admin
        vm.prank(nonAdminUser);

        // Attempt to rescue tokens and expect revert
        vm.expectRevert("Not owner");
        hook.rescue(tokenAddress, rescueAmount);
    }

    function test_RescueWithZeroAmount() public {
        // Setup
        uint256 rescueAmount = 0;
        address tokenAddress = Currency.unwrap(token0);

        // Act as admin
        vm.prank(adminAddress);

        // Attempt to rescue with zero amount and expect revert
        vm.expectRevert("Zero amount");
        hook.rescue(tokenAddress, rescueAmount);
    }

    function test_RescueMoreThanBalance() public {
        // Setup
        address tokenAddress = Currency.unwrap(token0);
        uint256 hookBalance = IERC20(tokenAddress).balanceOf(address(hook));
        uint256 rescueAmount = hookBalance + 1;

        // Act as admin
        vm.prank(adminAddress);

        // Attempt to rescue more than available and expect revert
        vm.expectRevert("Insufficient balance");
        hook.rescue(tokenAddress, rescueAmount);
    }

    function test_RescueEntireBalance() public {
        // Setup
        address tokenAddress = Currency.unwrap(token0);
        uint256 hookBalance = IERC20(tokenAddress).balanceOf(address(hook));
        uint256 adminBalanceBefore = IERC20(tokenAddress).balanceOf(adminAddress);

        // Act as admin
        vm.prank(adminAddress);

        // Rescue entire balance
        hook.rescue(tokenAddress, hookBalance);

        // Verify balances
        uint256 hookBalanceAfter = IERC20(tokenAddress).balanceOf(address(hook));
        uint256 adminBalanceAfter = IERC20(tokenAddress).balanceOf(adminAddress);

        assertEq(hookBalanceAfter, 0, "Hook balance should be zero");
        assertEq(adminBalanceAfter, adminBalanceBefore + hookBalance, "Admin balance should increase by hook balance");
    }

    function test_RescueDifferentToken() public {
        // Setup - token1 is the different token
        uint256 rescueAmount = 700;
        address token1Address = Currency.unwrap(token1);

        // Give some token1 to the hook
        deal(token1Address, address(hook), 1000, false);

        uint256 hookBalanceBefore = IERC20(token1Address).balanceOf(address(hook));
        uint256 adminBalanceBefore = IERC20(token1Address).balanceOf(adminAddress);

        // Act as admin
        vm.prank(adminAddress);

        // Rescue tokens
        hook.rescue(token1Address, rescueAmount);

        // Verify balances
        uint256 hookBalanceAfter = IERC20(token1Address).balanceOf(address(hook));
        uint256 adminBalanceAfter = IERC20(token1Address).balanceOf(adminAddress);

        assertEq(hookBalanceAfter, hookBalanceBefore - rescueAmount, "Hook balance should decrease by rescue amount");
        assertEq(adminBalanceAfter, adminBalanceBefore + rescueAmount, "Admin balance should increase by rescue amount");
    }
}
