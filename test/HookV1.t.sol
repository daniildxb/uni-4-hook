// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {HookV1} from "../src/HookV1.sol";

contract HookV1Test is Test, Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency token0;
    Currency token1;
    int24 tickMin = -3000;
    int24 tickMax = 3000;
    address aavePoolAddressesProvider = address(4);
    string shareName = "name";
    string shareSymbol = "symbol";
    HookV1 hook;

    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    function setUp() public {
        deployFreshManagerAndRouters();
        (token0, token1) = deployMintAndApprove2Currencies();
        _deployHook();

        (simpleKey, simplePoolId) = initPool(token0, token1, IHooks(hook), 3000, SQRT_PRICE_1_1);
        hook.addPool(simpleKey);
    }

    function _deployHook() internal {
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(
            address(manager), token0, token1, tickMin, tickMax, aavePoolAddressesProvider, shareName, shareSymbol
        ); //Add all the necessary constructor arguments from the hook
        deployCodeTo("HookV1.sol:HookV1", constructorArgs, flags);
        hook = HookV1(flags);
    }

    function test_construction() public {
        assertNotEq(address(hook), address(0));
    }

    function test_cannot_add_liquidity_directly() public {
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(simpleKey, LIQUIDITY_PARAMS, abi.encode(0));
    }

    function test_add_liquidity_through_hook() public {
        console.log("Adding liquidity through hook");
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));
        console.log("address of runner", address(this));
        console.log("Token0 balance before: ", balance0);
        console.log("Token1 balance before: ", balance1);
        IERC20(Currency.unwrap(token0)).approve(address(hook), 1000);
        IERC20(Currency.unwrap(token1)).approve(address(hook), 1000);
        hook.addLiquidity(IPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 3000, liquidityDelta: 1000, salt: 0}));

        uint256 balance0New = token0.balanceOf(address(this));
        uint256 balance1New = token1.balanceOf(address(this));

        console.log("balance diff", balance0 - balance0New);
        console.log("balance diff", balance1 - balance1New);

        uint256 expectedDiff = 139; // hardcoded based on the ticks and current price
        assertEq(balance0New, balance0 - expectedDiff); // hardcoded based on the ticks and current price
        assertEq(balance1New, balance1 - expectedDiff);

        // position is not provisioned on the liqudity add
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            manager.getPositionInfo(simplePoolId, address(hook), int24(0), int24(60), 0);

        assertEq(liquidity, 0);
        assertEq(feeGrowthInside0LastX128, 0);
        assertEq(feeGrowthInside1LastX128, 0);
    }

    function test_liqudity_is_added_before_swap() public {
        uint256 balance0 = token0.balanceOf(address(this));
        uint256 balance1 = token1.balanceOf(address(this));

        IERC20(Currency.unwrap(token0)).approve(address(hook), 1000);
        IERC20(Currency.unwrap(token1)).approve(address(hook), 1000);
        hook.addLiquidity(IPoolManager.ModifyLiquidityParams({tickLower: 0, tickUpper: 60, liquidityDelta: 1000, salt: 0}));

        uint256 balance0New = token0.balanceOf(address(this));
        uint256 balance1New = token1.balanceOf(address(this));

        console.log("balance diff", balance0 - balance0New);
        console.log("balance diff", balance1 - balance1New);

        uint256 expectedDiff = 139; // hardcoded based on the ticks and current price
        assertEq(balance0New, balance0 - expectedDiff); // hardcoded based on the ticks and current price
        assertEq(balance1New, balance1 - expectedDiff);

        console.log("hook balance0", token0.balanceOf(address(hook)));
        console.log("hook balance1", token1.balanceOf(address(hook)));

        // swap

        bool zeroForOne = true;
        int256 amountSpecified = 100; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(simpleKey, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //
        console.log("Swap delta amount0: ", swapDelta.amount0());
        console.log("Swap delta amount1: ", swapDelta.amount1());


    }
}
