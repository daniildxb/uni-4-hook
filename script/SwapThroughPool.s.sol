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
import {HookV1} from "../src/HookV1.sol";

/// @notice Swaps through the pool
/// todo: handle recent changes to config structure
contract SwapThroughPoolScript is Script, Deployers, Config {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    // amount to receive after swap !!
    int256 amountToSwap = 1 * 1e6;


    function run() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        Config.ConfigData memory config = getConfigPerNetwork(chainId);
        HookV1 hook = HookV1(address(config.poolKey.hooks));

        console.log("1");
        uint256 shares = hook.balanceOf(receiver);
        console.log("2");
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        console.log("3");
        deploySwapRouter(config);
        console.log("4");

        // approve the swap router
        IERC20(Currency.unwrap(hook.token1())).forceApprove(address(swapRouter), uint256(amountToSwap + 100));
        console.log("5");
        swap(config.poolKey, false, amountToSwap, ZERO_BYTES);
        console.log("6");
        vm.stopBroadcast();
    }

    // do it only once and then reuse
    function deploySwapRouter(Config.ConfigData memory config) public {
        swapRouter = new PoolSwapTest(IPoolManager(config.poolManager));
    }
}
