// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";

/// @notice Swaps through the pool
/// This script handles token decimals automatically
contract SwapThroughPoolScript is Script, Deployers, Config {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // Amount to swap is calculated dynamically based on token decimals
    int256 public amountToSwap0;
    int256 public amountToSwap1;

    function run() public {
        // Parse the AMOUNT environment variable if provided
        string memory amountArg = vm.envOr("AMOUNT", string("100000")); // Default to 100000 if not provided
        int256 baseAmountToSwap = int256(vm.parseUint(amountArg));

        // Get the pool enum from environment variables or default to USDC/USDT pool
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envOr("POOL_ENUM", uint256(0)); // Default to USDC/USDT pool (0)

        Config.ConfigData memory config = getConfigPerNetwork(chainId, pool_enum);
        ModularHookV1 hook = ModularHookV1(address(config.poolKey.hooks));

        // Get token decimals
        uint8 decimals0 = IERC20Metadata(Currency.unwrap(hook.token0())).decimals();
        uint8 decimals1 = IERC20Metadata(Currency.unwrap(hook.token1())).decimals();

        // Calculate amount to swap based on token decimals
        amountToSwap0 = baseAmountToSwap * int256(10 ** decimals0) / 1e6; // Scale from 6 decimals
        amountToSwap1 = baseAmountToSwap * int256(10 ** decimals1) / 1e6; // Scale from 6 decimals

        console.log("Token0 decimals:", decimals0);
        console.log("Token1 decimals:", decimals1);

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
        console.log("Performing swap token1 -> token0 with amount:", uint256(amountToSwap1));
        swap(config.poolKey, false, -amountToSwap1, ZERO_BYTES);

        // token0 -> token1 (negative for exact input swap)
        console.log("Performing swap token0 -> token1 with amount:", uint256(amountToSwap0));
        swap(config.poolKey, true, -amountToSwap0, ZERO_BYTES);

        console.log("6");
        vm.stopBroadcast();
    }

    // do it only once and then reuse
    function deploySwapRouter(Config.ConfigData memory config) public {
        // swapRouter = new PoolSwapTest(IPoolManager(config.poolManager));
        swapRouter = PoolSwapTest(0xf719c9761e6e6D03F9867F8a1fBEE04D5d34ceBb);
    }
}