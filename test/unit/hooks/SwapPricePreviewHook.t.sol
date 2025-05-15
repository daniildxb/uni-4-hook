// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {RescueHook} from "../../../src/hooks/RescueHook.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";

/**
 * @notice Test swap price preview hook functionality
 */
contract SwapPricePreviewHookTest is BaseTest {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;

    function test_previewShouldBeAccurate() public {
        // setup
        uint256 depositAmount = 100 * 1e6;
        deal(Currency.unwrap(token0), user1, depositAmount, false);
        deal(Currency.unwrap(token1), user1, depositAmount, false);
        depositTokensToHook(depositAmount, depositAmount, user1);

        // preview swap
        int256 swapAmount = 1 * 1e6;
        deal(Currency.unwrap(token0), user1, uint256(swapAmount * 2), false);
        deal(Currency.unwrap(token1), user1, uint256(swapAmount * 2), false);

        bool zeroForOne = true;

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({amountSpecified: swapAmount, zeroForOne: zeroForOne, sqrtPriceLimitX96: 0});

        (BalanceDelta previewSwapDelta, uint24 previewSwapFee, Pool.SwapResult memory previewResult) =
            hook.previewSwap(swapParams);

        vm.startPrank(user1);
        IERC20(Currency.unwrap(token0)).forceApprove(address(swapRouter), uint256(swapAmount * 2));
        IERC20(Currency.unwrap(token1)).forceApprove(address(swapRouter), uint256(swapAmount * 2));

        BalanceDelta swapDelta = swap(simpleKey, zeroForOne, swapAmount, ZERO_BYTES);
        vm.stopPrank();

        console.log("previewSwapDelta: ");
        console.log(previewSwapDelta.amount0());
        console.log(previewSwapDelta.amount1());
        console.log("swapDelta: ");
        console.log(swapDelta.amount0());
        console.log(swapDelta.amount1());
        assertEq(
            previewSwapDelta.amount0(),
            swapDelta.amount0(),
            "previewSwapDelta amount0 should be equal to swapDelta amount0"
        );
        assertEq(
            previewSwapDelta.amount1(),
            swapDelta.amount1(),
            "previewSwapDelta amount1 should be equal to swapDelta amount1"
        );
        assert(true);
    }

    function test_shouldFailIfNotEnoughLiquidity() public {
        // setup
        uint256 depositAmount = 100 * 1e6;
        deal(Currency.unwrap(token0), user1, depositAmount, false);
        deal(Currency.unwrap(token1), user1, depositAmount, false);
        depositTokensToHook(depositAmount, depositAmount, user1);

        // preview swap
        int256 swapAmount = 1000 * 1e6;
        deal(Currency.unwrap(token0), user1, uint256(swapAmount * 2), false);
        deal(Currency.unwrap(token1), user1, uint256(swapAmount * 2), false);

        bool zeroForOne = true;

        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({amountSpecified: swapAmount, zeroForOne: zeroForOne, sqrtPriceLimitX96: 0});

        // should fail for zero for one
        {
            vm.expectRevert("Not enough token0");
            (BalanceDelta swapDelta, uint24 swapFee, Pool.SwapResult memory result) = hook.previewSwap(swapParams);
        }
        swapParams.zeroForOne = false;
        {
            vm.expectRevert("Not enough token1");
            (BalanceDelta swapDelta, uint24 swapFee, Pool.SwapResult memory result) = hook.previewSwap(swapParams);
        }
    }
}
