// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseTest} from "../../BaseTest.sol";
import {ModularHookV1} from "../../../src/ModularHookV1.sol";

contract DepositCapHookTest is BaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // Test users
    address public depositUser = address(777);

    function setUp() public override {
        super.setUp();

        // Give tokens to test user
        deal(Currency.unwrap(token0), depositUser, initialTokenBalance * 10, false);
        deal(Currency.unwrap(token1), depositUser, initialTokenBalance * 10, false);
    }

    function test_deposit_caps_disabled_by_default() public {
        // Check that deposit caps are 0 (disabled) by default
        uint256 depositCap0 = ModularHookV1(address(hook)).depositCap0();
        uint256 depositCap1 = ModularHookV1(address(hook)).depositCap1();
        assertEq(depositCap0, 0, "Deposit cap for token0 should be 0 by default");
        assertEq(depositCap1, 0, "Deposit cap for token1 should be 0 by default");

        // Large deposit should succeed when caps are disabled
        uint256 depositAmount = initialTokenBalance * 2;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        vm.startPrank(depositUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should not revert since deposit caps are disabled
        hook.deposit(depositAmount, depositUser);
        vm.stopPrank();

        // Verify deposit was successful
        uint256 userShares = ModularHookV1(address(hook)).balanceOf(depositUser);
        assertEq(userShares, depositAmount, "User should be able to deposit when caps are disabled");
    }

    function test_set_deposit_caps() public {
        // Set deposit caps as admin
        uint256 newCap0 = 1000;
        uint256 newCap1 = 1000;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(newCap0, newCap1);
        vm.stopPrank();

        // Verify caps are set
        uint256 depositCap0 = ModularHookV1(address(hook)).depositCap0();
        uint256 depositCap1 = ModularHookV1(address(hook)).depositCap1();
        assertEq(depositCap0, newCap0, "Deposit cap for token0 should be set");
        assertEq(depositCap1, newCap1, "Deposit cap for token1 should be set");
    }

    function test_deposit_within_cap() public {
        // Set deposit caps
        uint256 capAmount = 1000;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(capAmount, capAmount);
        vm.stopPrank();

        // Try to deposit just under the cap
        uint256 depositAmount = 600; // This will translate to token amounts less than 1000
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        // Make sure token amounts are within caps
        assertLt(token0Amount, capAmount, "Token0 amount should be within cap");
        assertLt(token1Amount, capAmount, "Token1 amount should be within cap");

        vm.startPrank(depositUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should not revert since deposit is within cap
        hook.deposit(depositAmount, depositUser);
        vm.stopPrank();

        // Verify deposit was successful
        uint256 userShares = ModularHookV1(address(hook)).balanceOf(depositUser);
        assertEq(userShares, depositAmount, "User should be able to deposit when within cap");
    }

    function test_deposit_exceeds_token0_cap() public {
        // Set low deposit cap for token0
        uint256 cap0 = 50;
        uint256 cap1 = 1000;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(cap0, cap1);
        vm.stopPrank();

        // Try to deposit an amount that exceeds token0 cap
        uint256 depositAmount = 500;
        depositTokensToHookExpectRevert(depositAmount, depositAmount, depositUser);
    }

    function test_deposit_exceeds_token1_cap() public {
        // Set low deposit cap for token1
        uint256 cap0 = 1000;
        uint256 cap1 = 50;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(cap0, cap1);
        vm.stopPrank();

        // Try to deposit an amount that exceeds token0 cap
        uint256 depositAmount = 500;
        depositTokensToHookExpectRevert(depositAmount, depositAmount, depositUser);
    }

    function test_multiple_deposits_up_to_cap() public {
        // Set deposit caps
        uint256 capAmount = 200;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(capAmount, capAmount);
        vm.stopPrank();

        // Make multiple deposits up to just under the cap
        uint256 depositAmount1 = 70; // Will result in ~70 token amounts
        depositTokensToHook(depositAmount1, depositAmount1, depositUser);

        // Try a second deposit that should bring us to the cap
        depositTokensToHook(depositAmount1, depositAmount1, depositUser);

        depositTokensToHookExpectRevert(depositAmount1, depositAmount1, depositUser);
    }

    function test_update_deposit_caps() public {
        // First set low deposit caps
        uint256 initialCap = 100;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(initialCap, initialCap);
        vm.stopPrank();

        // Try a deposit that should fail due to cap
        uint256 largeDeposit = 1000;
        depositTokensToHookExpectRevert(largeDeposit, largeDeposit, depositUser);

        // Now increase the caps
        uint256 newCap = 1000;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(newCap, newCap);
        vm.stopPrank();

        depositTokensToHook(largeDeposit, largeDeposit, depositUser);
    }

    function test_disable_deposit_caps() public {
        // First set deposit caps
        uint256 capAmount = 100;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(capAmount, capAmount);
        vm.stopPrank();

        // Verify caps are set
        uint256 depositCap0 = ModularHookV1(address(hook)).depositCap0();
        uint256 depositCap1 = ModularHookV1(address(hook)).depositCap1();
        assertEq(depositCap0, capAmount, "Deposit cap for token0 should be set");
        assertEq(depositCap1, capAmount, "Deposit cap for token1 should be set");

        // Now disable caps by setting to 0
        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(0, 0);
        vm.stopPrank();

        // Verify caps are 0
        depositCap0 = ModularHookV1(address(hook)).depositCap0();
        depositCap1 = ModularHookV1(address(hook)).depositCap1();
        assertEq(depositCap0, 0, "Deposit cap for token0 should be 0");
        assertEq(depositCap1, 0, "Deposit cap for token1 should be 0");

        // Large deposit should succeed now that caps are disabled
        uint256 largeDeposit = 1000;
        (uint256 token0Amount, uint256 token1Amount) = getTokenAmountsForLiquidity(largeDeposit);

        vm.startPrank(depositUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), token0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), token1Amount);

        // Should not revert since caps are disabled
        hook.deposit(largeDeposit, depositUser);
        vm.stopPrank();

        // Verify deposit was successful
        uint256 userShares = ModularHookV1(address(hook)).balanceOf(depositUser);
        assertEq(userShares, largeDeposit, "User should be able to deposit when caps are disabled");
    }

    function test_only_admin_can_set_deposit_caps() public {
        // Try to set deposit caps as non-admin
        vm.startPrank(depositUser);
        vm.expectRevert("Not hook manager");
        ModularHookV1(address(hook)).setDepositCaps(1000, 1000);
        vm.stopPrank();
    }
}
