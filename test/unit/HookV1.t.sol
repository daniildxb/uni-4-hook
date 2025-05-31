// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ModularHookV1} from "../../src/ModularHookV1.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {BaseTest} from "../BaseTest.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HookV1Test is BaseTest {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    address public allowedUser = address(777);
    address public nonAllowedUser = address(888);

    function test_construction() public {
        assertNotEq(address(hook), address(0));
    }

    function test_cannot_add_liquidity_directly() public {
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQUIDITY_PARAMS, abi.encode(0));
    }

    function test_add_liquidity_through_hook() public {
        console.log("Adding liquidity through hook");
        deal(Currency.unwrap(token0), address(manager), 1000, false);
        deal(Currency.unwrap(token1), address(manager), 1000, false);

        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        console.log("address of runner", address(this));
        console.log("Token0 balance before: ", balance0);
        console.log("Token1 balance before: ", balance1);
        IERC20(Currency.unwrap(token0)).forceApprove(address(hook), 1000);
        IERC20(Currency.unwrap(token1)).forceApprove(address(hook), 1000);
        (uint256 sharesMinted,,,) = depositTokensToHook(140, 140, address(this));

        uint256 balance0New = token0.balanceOf(address(this));
        uint256 balance1New = token1.balanceOf(address(this));

        console.log("balance diff", balance0 - balance0New);
        console.log("balance diff", balance1 - balance1New);

        uint256 expectedDiff = 140; // hardcoded based on the ticks and current price
        assertEq(balance0New, balance0 - expectedDiff); // hardcoded based on the ticks and current price
        assertEq(balance1New, balance1 - expectedDiff);

        // position is not provisioned on the liqudity add
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            manager.getPositionInfo(simplePoolId, address(hook), int24(0), int24(60), 0);

        assertEq(liquidity, 0);
        assertEq(feeGrowthInside0LastX128, 0);
        assertEq(feeGrowthInside1LastX128, 0);

        hook.redeem(sharesMinted, address(this), address(this));

        // 1 unit of assets is lost in the rounding
        assertEq(token0.balanceOf(address(this)), balance0 - 1, "test runner token0 balance after LP removal");
        assertEq(token1.balanceOf(address(this)), balance1 - 1, "test runner token1 balance after LP removal");
        uint256 sharesAfterRedeem = IERC20(address(hook)).balanceOf(address(this));
        assertEq(sharesAfterRedeem, 0, "test runner shares after LP removal");
    }

    function test_liqudity_is_added_before_swap() public {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        uint256 depositAmount = 1000;

        deal(Currency.unwrap(token0), address(manager), depositAmount, false);
        deal(Currency.unwrap(token1), address(manager), depositAmount, false);

        IERC20(Currency.unwrap(token0)).forceApprove(address(hook), depositAmount);
        IERC20(Currency.unwrap(token1)).forceApprove(address(hook), depositAmount);

        depositTokensToHook(depositAmount, depositAmount, address(this));

        uint256 balance0New = token0.balanceOf(address(this));
        uint256 balance1New = token1.balanceOf(address(this));

        console.log("balance diff", balance0 - balance0New);
        console.log("balance diff", balance1 - balance1New);

        assertEq(balance0New, balance0 - depositAmount);
        assertEq(balance1New, balance1 - depositAmount);

        console.log("hook balance0", token0.balanceOf(address(hook)));
        console.log("hook balance1", token1.balanceOf(address(hook)));

        // swap

        bool zeroForOne = true;
        int256 amountSpecified = 100; // negative number indicates exact input swap!

        IERC20(Currency.unwrap(token0)).forceApprove(address(swapRouter), 1000);
        IERC20(Currency.unwrap(token1)).forceApprove(address(swapRouter), 1000);

        BalanceDelta swapDelta = swap(simpleKey, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //
        console.log("Swap delta amount0: ", swapDelta.amount0());
        console.log("Swap delta amount1: ", swapDelta.amount1());

        uint256 balance0AfterSwap = token0.balanceOf(address(this));
        uint256 balance1AfterSwap = token1.balanceOf(address(this));

        console.log("balance diff after swap", balance0New - balance0AfterSwap);
        console.log("balance diff after swap", balance1AfterSwap - balance1New);

        BalanceDelta swapDelta2 = swap(simpleKey, false, amountSpecified, ZERO_BYTES);
        // todo: add asserts about after swap state
    }

    /**
     * @notice Test scenario where:
     * 1. User 1 deposits into a new pool
     * 2. User 2 deposits into a pool with 2x amount of User 1
     * 3. Value of shares user 1 has is not affected by that deposit
     */
    function test_share_value_remains_stable_after_new_deposits() public {
        // First, ensure the pool manager has some tokens
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // 1. User 1 deposits into the pool
        uint256 user1DepositAmount = 1e8;
        deal(Currency.unwrap(token0), user1, user1DepositAmount, false);
        deal(Currency.unwrap(token1), user1, user1DepositAmount, false);

        (,, int128 user1amount0, int128 user1amount1) =
            depositTokensToHook(user1DepositAmount, user1DepositAmount, user1);

        // Record User 1's initial share balance and value
        uint256 user1InitialShares = IERC20(address(hook)).balanceOf(user1);

        // Calculate initial asset value of User 1's shares
        uint256 user1InitialAssetValue = hook.convertToAssets(user1InitialShares);

        // 2. User 2 deposits into the pool with 2x the amount of User 1
        uint256 user2DepositAmount = user1DepositAmount * 2;
        deal(Currency.unwrap(token0), user2, user2DepositAmount, false);
        deal(Currency.unwrap(token1), user2, user2DepositAmount, false);

        (,, int128 user2amount0, int128 user2amount1) =
            depositTokensToHook(user2DepositAmount, user2DepositAmount, user2);

        // Verify User 2 deposited approximately twice as many tokens
        assertApproxEqAbs(user2amount0, user1amount0 * 2, 1, "User 2 should deposit ~2x token0 amount");
        assertApproxEqAbs(user2amount1, user1amount1 * 2, 1, "User 2 should deposit ~2x token1 amount");

        // Record User 2's share balance
        uint256 user2Shares = ModularHookV1(address(hook)).balanceOf(user2);

        assertApproxEqAbs(
            user2Shares,
            user1InitialShares * 2,
            1,
            "User 2 should have received shares approximately equal to 2x User 1's shares"
        );

        // 3. Verify the value of User 1's shares has not been diluted
        uint256 user1FinalAssetValue = hook.convertToAssets(user1InitialShares);
        assertApproxEqAbs(
            user1FinalAssetValue,
            user1InitialAssetValue,
            2,
            "User 1's share value should remain the same after User 2's deposit"
        );

        // Additional verification: ensure the share price is consistent between users
        uint256 user1ValuePerShare = user1FinalAssetValue / user1InitialShares;
        uint256 user2ValuePerShare = hook.convertToAssets(user2Shares) / user2Shares;
        assertApproxEqAbs(
            user1ValuePerShare, user2ValuePerShare, 1, "Value per share should be consistent between users"
        );

        // Verify User 2 has approximately twice as many shares as User 1
        assertApproxEqAbs(
            user2Shares, user1InitialShares * 2, 1, "User 2 should have approximately 2x the shares of User 1"
        );

        // Verify token balances in the hook increased proportionally
        TokenBalances memory finalBalances = getBalances(address(0));
        assertGt(finalBalances.hookToken0, 0, "Hook should have token0 balance");
        assertGt(finalBalances.hookToken1, 0, "Hook should have token1 balance");

        // Check that both users can redeem their shares
        // User 1 redeems shares
        vm.startPrank(user1);
        hook.redeem(user1InitialShares, user1, user1);
        vm.stopPrank();

        // User 2 redeems shares
        vm.startPrank(user2);
        hook.redeem(user2Shares, user2, user2);
        vm.stopPrank();

        // Verify both users got their tokens back (minus fees and rounding)
        TokenBalances memory finalUserBalances = getBalances(user1);
        assertGt(finalUserBalances.userToken0, 0, "User1 should have received token0 back");
        assertGt(finalUserBalances.userToken1, 0, "User1 should have received token1 back");

        finalUserBalances = getBalances(user2);
        assertGt(finalUserBalances.userToken0, 0, "User2 should have received token0 back");
        assertGt(finalUserBalances.userToken1, 0, "User2 should have received token1 back");
    }

    /**
     * @notice Similar test with a more detailed breakdown of share values
     */
    function test_share_value_calculation_with_multiple_deposits() public {
        // Setup the initial state
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // 1. First deposit by User 1
        uint256 user1DepositAmount = 1e4;
        (uint256 token0Amount1, uint256 token1Amount1,,) = depositLiquidity(user1, user1DepositAmount);
        console.log("User 1 deposited token0:", token0Amount1);
        console.log("User 1 deposited token1:", token1Amount1);

        {
            uint256 totalAssets = hook.totalAssets();
            uint256 unclaimedFees = hook.unclaimedFees();
            console.log("Total assets in hook:", totalAssets);
            console.log("Unclaimed fees in hook:", unclaimedFees);
        }

        // Record initial shares and values
        uint256 user1Shares = IERC20(address(hook)).balanceOf(user1);
        uint256 totalSupplyAfterUser1 = IERC20(address(hook)).totalSupply();
        console.log("User 1 shares:", user1Shares);
        console.log("Total supply after User 1 deposit:", totalSupplyAfterUser1);

        // Calculate share value
        uint256 user1ShareValue = hook.convertToAssets(user1Shares);

        console.log("User 1 share value in assets:", user1ShareValue);
        {
            (int128 token0ValueAfterDeposit, int128 token1ValueAfterDeposit) =
                hook.getTokenAmountsForLiquidity(user1ShareValue);
            console.log("User 1 token0 value after deposit:", -token0ValueAfterDeposit);
            console.log("User 1 token1 value after deposit:", -token1ValueAfterDeposit);
        }

        // 2. Second deposit by User 2 (2x the amount)
        uint256 user2DepositAmount = user1DepositAmount * 2;
        (uint256 token0Amount2, uint256 token1Amount2,,) = depositLiquidity(user2, user2DepositAmount);
        console.log("User 2 deposited token0:", token0Amount2);
        console.log("User 2 deposited token1:", token1Amount2);

        {
            uint256 totalAssets = hook.totalAssets();
            uint256 unclaimedFees = hook.unclaimedFees();
            console.log("Total assets in hook:", totalAssets);
            console.log("Unclaimed fees in hook:", unclaimedFees);
        }

        // Record User 2's shares
        uint256 user2Shares = IERC20(address(hook)).balanceOf(user2);
        uint256 totalSupplyAfterUser2 = IERC20(address(hook)).totalSupply();
        console.log("User 2 shares:", user2Shares);
        console.log("Total supply after User 2 deposit:", totalSupplyAfterUser2);

        // Calculate User 2's share value
        uint256 user2ShareValue = hook.convertToAssets(user2Shares);
        console.log("User 2 share value in assets:", user2ShareValue);
        {
            (int128 u2token0ValueAfterDeposit, int128 u2token1ValueAfterDeposit) =
                hook.getTokenAmountsForLiquidity(user1ShareValue);
            console.log("User 2 token0 value after deposit:", -u2token0ValueAfterDeposit);
            console.log("User 2 token1 value after deposit:", -u2token1ValueAfterDeposit);
        }

        // 3. Check share values after both deposits
        uint256 user1ShareValueAfterUser2 = hook.convertToAssets(user1Shares);
        console.log("User 1 share value after User 2 deposit:", user1ShareValueAfterUser2);

        {
            (int128 u1token0ValueAfterUser2, int128 u1token1ValueAfterUser2) =
                hook.getTokenAmountsForLiquidity(user1ShareValueAfterUser2);
            console.log("User 1 token0 value after User 2 deposit:", -u1token0ValueAfterUser2);
            console.log("User 1 token1 value after User 2 deposit:", -u1token1ValueAfterUser2);
        }

        // 4. Compare share values
        console.log("User 1 share value change:", int256(user1ShareValueAfterUser2) - int256(user1ShareValue));
        console.log("Share value ratio (User2/User1):", (user2ShareValue * 1e18) / user1ShareValueAfterUser2);

        // Assertions to verify share values remain fair
        assertApproxEqAbs(
            user1ShareValueAfterUser2,
            user1ShareValue,
            1,
            "User 1's share value should remain stable after User 2's deposit"
        );

        assertApproxEqAbs(
            user2ShareValue, user1ShareValueAfterUser2 * 2, 1, "User 2's share value should be ~2x User 1's share value"
        );

        // Check that redeeming shares works correctly
        vm.startPrank(user1);
        uint256 assets1Before = IERC20(token0Address).balanceOf(user1) + IERC20(token1Address).balanceOf(user1);
        hook.redeem(user1Shares, user1, user1);
        uint256 assets1After = IERC20(token0Address).balanceOf(user1) + IERC20(token1Address).balanceOf(user1);
        console.log("User 1 redeemed assets:", assets1After - assets1Before);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 assets2Before = IERC20(token0Address).balanceOf(user2) + IERC20(token1Address).balanceOf(user2);
        hook.redeem(user2Shares, user2, user2);
        uint256 assets2After = IERC20(token0Address).balanceOf(user2) + IERC20(token1Address).balanceOf(user2);
        console.log("User 2 redeemed assets:", assets2After - assets2Before);
        vm.stopPrank();

        // Verify redeemed assets are proportional to deposits
        assertApproxEqAbs(
            (assets2After - assets2Before),
            (assets1After - assets1Before) * 2,
            4, // compounding from other 1 deltas ; todo: verify
            "User 2 should redeem ~2x the assets of User 1"
        );
    }

    // New tests for the combined functionality

    /**
     * @notice Test scenario where:
     * 1. Admin enables allowlist and adds an allowlisted user
     * 2. Admin sets deposit caps
     * 3. Allowlisted user can deposit within caps
     * 4. Non-allowlisted user cannot deposit
     * 5. Allowlisted user cannot exceed deposit caps
     */
    function test_allowlist_and_deposit_cap_combined() public {
        // Setup initial state
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // Set deposit caps
        uint256 depositCap = 150;
        uint256 allowListedUserShares = 0;
        uint256 nonAllowListedUserShares = 0;

        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(depositCap, depositCap);

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
            assertEq(cap0, depositCap, "Deposit cap0 should be set");
            assertEq(cap1, depositCap, "Deposit cap1 should be set");
        }

        // Test 1: Non-allowlisted user cannot deposit
        uint256 smallDeposit = 500;
        (uint256 smallToken0Amount, uint256 smallToken1Amount) = getTokenAmountsForLiquidity(smallDeposit);

        vm.startPrank(nonAllowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), smallToken0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), smallToken1Amount);

        // Should revert because user is not allowlisted
        vm.expectRevert("Not allowed");
        nonAllowListedUserShares += hook.deposit(smallDeposit, nonAllowedUser, ZERO_BYTES);
        vm.stopPrank();

        // Test 2: Allowlisted user can deposit within caps
        vm.startPrank(allowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), smallToken0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), smallToken1Amount);

        // Should succeed because user is allowlisted and within caps
        allowListedUserShares += hook.deposit(smallDeposit, allowedUser, ZERO_BYTES);
        vm.stopPrank();

        // Verify successful deposit
        uint256 allowedUserShares = ModularHookV1(address(hook)).balanceOf(allowedUser);
        assertEq(allowedUserShares, allowListedUserShares, "Allowlisted user's deposit within caps should succeed");

        // Test 3: Allowlisted user cannot exceed deposit caps
        uint256 largeDeposit = 1000;
        depositTokensToHookExpectRevert(largeDeposit, largeDeposit, allowedUser);

        // Test 4: Disabling allowlist should still enforce deposit caps
        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        vm.startPrank(nonAllowedUser);
        IERC20(Currency.unwrap(token0)).approve(address(hook), smallToken0Amount);
        IERC20(Currency.unwrap(token1)).approve(address(hook), smallToken1Amount);

        // Should succeed now that allowlist is disabled, but still under caps
        nonAllowListedUserShares += hook.deposit(smallDeposit, nonAllowedUser, ZERO_BYTES);
        vm.stopPrank();

        // Verify non-allowlisted user's deposit succeeded
        uint256 nonAllowedUserShares = ModularHookV1(address(hook)).balanceOf(nonAllowedUser);
        assertEq(
            nonAllowedUserShares,
            nonAllowListedUserShares,
            "Non-allowlisted user's deposit should succeed when allowlist is disabled"
        );

        // Test 5: Removing deposit caps but keeping allowlist
        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(0, 0);
        ModularHookV1(address(hook)).flipAllowlist();
        vm.stopPrank();

        // Try large deposit with allowlisted user
        (uint256 largeDepositShares,,,) = depositTokensToHook(largeDeposit, largeDeposit, allowedUser);
        allowListedUserShares += largeDepositShares;
        // Verify large deposit succeeded
        uint256 allowedUserSharesAfterLargeDeposit = ModularHookV1(address(hook)).balanceOf(allowedUser);
        assertEq(
            allowedUserSharesAfterLargeDeposit,
            allowListedUserShares,
            "Allowlisted user's large deposit should succeed when caps are removed"
        );

        // Try large deposit with non-allowlisted user
        depositTokensToHookExpectRevert(largeDeposit, largeDeposit, nonAllowedUser);
    }
}
