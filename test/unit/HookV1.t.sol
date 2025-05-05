// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {BaseTest} from "../BaseTest.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HookV1Test is BaseTest {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

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
        hook.deposit(1000, address(this));

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

        uint256 sharesMinted = IERC20(address(hook)).balanceOf(address(this));
        // whn issuing initial shares they are issued 1:1 to assets (liquidity)
        assertEq(sharesMinted, 1000);

        hook.redeem(1000, address(this), address(this));

        // 1 unit of assets is lost in the rounding
        assertEq(token0.balanceOf(address(this)), balance0 - 1, "test runner token0 balance after LP removal");
        assertEq(token1.balanceOf(address(this)), balance1 - 1, "test runner token1 balance after LP removal");
        uint256 sharesAfterRedeem = IERC20(address(hook)).balanceOf(address(this));
        assertEq(sharesAfterRedeem, 0, "test runner shares after LP removal");
    }

    function test_liqudity_is_added_before_swap() public {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        deal(Currency.unwrap(token0), address(manager), 1000, false);
        deal(Currency.unwrap(token1), address(manager), 1000, false);

        IERC20(Currency.unwrap(token0)).forceApprove(address(hook), 1000);
        IERC20(Currency.unwrap(token1)).forceApprove(address(hook), 1000);
        hook.deposit(1000, msg.sender);

        uint256 balance0New = token0.balanceOf(address(this));
        uint256 balance1New = token1.balanceOf(address(this));

        console.log("balance diff", balance0 - balance0New);
        console.log("balance diff", balance1 - balance1New);

        uint256 expectedDiff = 140; // hardcoded based on the ticks and current price
        assertEq(balance0New, balance0 - expectedDiff); // hardcoded based on the ticks and current price
        assertEq(balance1New, balance1 - expectedDiff);

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
}
