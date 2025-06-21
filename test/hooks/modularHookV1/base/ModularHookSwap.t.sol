// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ModularHookBaseTest} from "./ModularHookBaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title ModularHookSwapTest
 * @notice Tests for swap functionality in ModularHookV1
 */
contract ModularHookSwapTest is ModularHookBaseTest {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    /**
     * @notice Tests that liquidity is added to the pool before a swap happens
     * This ensures the pool has liquidity to support the swap
     */
    function test_liqudity_is_added_before_swap() public {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        deal(Currency.unwrap(token0), address(manager), depositAmount0(), false);
        deal(Currency.unwrap(token1), address(manager), depositAmount1(), false);

        IERC20(Currency.unwrap(token0)).forceApprove(address(hook), depositAmount0());
        IERC20(Currency.unwrap(token1)).forceApprove(address(hook), depositAmount1());

        depositTokensToHook(depositAmount0(), depositAmount1(), address(this));

        // Swap test
        bool zeroForOne = true;
        int256 amountSpecified = -int256(depositAmount0() / 10); // negative number indicates exact input swap

        uint256 hookBalance0 = token0.balanceOf(address(hook));
        uint256 hookBalance1 = token1.balanceOf(address(hook));

        BalanceDelta swapDelta = executeSwap(zeroForOne, amountSpecified);
    }

    /**
     * @notice Tests the impact of multiple swaps on liquidity providers
     * Verifies that fees accrue properly during swaps
     */
    function test_multiple_swaps_with_fee_accrual() public {
        // Initial setup and deposit - use much larger liquidity
        deal(Currency.unwrap(token0), address(manager), depositAmount0() * 20, false);
        deal(Currency.unwrap(token1), address(manager), depositAmount1() * 20, false);

        // Give user1 enough tokens for deposit and swaps
        deal(Currency.unwrap(token0), user1, depositAmount0() * 10, false);
        deal(Currency.unwrap(token1), user1, depositAmount1() * 10, false);

        // User 1 provides initial liquidity
        (uint256 user1Shares,,,) = depositTokensToHook(depositAmount0(), depositAmount1(), user1);

        // Record initial share value
        uint256 initialShareValue = hook.convertToAssets(user1Shares);
        console.log("Initial share value:", initialShareValue);

        // Execute multiple small swaps to generate fees with minimal price impact
        for (uint256 i = 0; i < 10; i++) {
            // Alternate swap direction
            bool zeroForOne = i % 2 == 0;
            // Use much smaller swap amounts relative to liquidity
            int256 swapAmount = zeroForOne ? int256(depositAmount0() / 10) : int256(depositAmount1() / 10);
            BalanceDelta swapDelta = executeSwap(zeroForOne, -swapAmount);
            console.log("Swap", i);
            console.log("delta0:", swapDelta.amount0());
            console.log("delta1:", swapDelta.amount1());
        }

        // Check if share value has increased due to fee accrual
        uint256 finalShareValue = hook.convertToAssets(user1Shares);
        console.log("Final share value:", finalShareValue);

        assertGe(finalShareValue, initialShareValue, "Share value should increase after swaps");
        // not adding asserts for withdrawals here, as pool composition has changed due to swaps
        // and withdrawal amounts will not be in the same ratio as deposits
    }
}
