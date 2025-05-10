// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";

/// @notice Swaps through the pool
/// todo: handle recent changes to config structure
contract SwapThroughPoolScript is Script, Deployers, Config {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // Amount to swap will be provided via CLI
    int256 public amountToSwap;

    function run() public {
        // Parse the AMOUNT environment variable if provided
        string memory amountArg = vm.envOr("AMOUNT", string("100000")); // Default to 1e5 if not provided
        amountToSwap = int256(vm.parseUint(amountArg));

        // Log the amount that will be used
        console.log("Amount to swap:", uint256(amountToSwap));

        uint256 chainId = vm.envUint("CHAIN_ID");
        Config.ConfigData memory config = getConfigPerNetwork(chainId);
        ModularHookV1 hook = ModularHookV1(address(config.poolKey.hooks));

        console.log("1");
        uint256 shares = hook.balanceOf(receiver);
        console.log("2");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        console.log("3");
        deploySwapRouter(config);
        console.log("4");

        // approve the swap router
        IERC20(Currency.unwrap(hook.token0())).forceApprove(address(swapRouter), uint256(type(uint256).max - 100));
        IERC20(Currency.unwrap(hook.token1())).forceApprove(address(swapRouter), uint256(type(uint256).max - 100));
        console.log("5");

        // token1 -> token0 (negative for exact input swap)
        console.log("Performing swap token1 -> token0 with amount:", uint256(amountToSwap));
        swap(config.poolKey, false, -amountToSwap, ZERO_BYTES);

        // token0 -> token1 (negative for exact input swap)
        console.log("Performing swap token0 -> token1 with amount:", uint256(amountToSwap));
        swap(config.poolKey, true, -amountToSwap, ZERO_BYTES);

        console.log("6");
        vm.stopBroadcast();
    }

    // do it only once and then reuse
    function deploySwapRouter(Config.ConfigData memory config) public {
        // swapRouter = new PoolSwapTest(IPoolManager(config.poolManager));
        swapRouter = PoolSwapTest(0xf719c9761e6e6D03F9867F8a1fBEE04D5d34ceBb);
    }
}
