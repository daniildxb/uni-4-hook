// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Config} from "./base/Config.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";
import {HookManager} from "src/HookManager.sol";

/// @notice Withdraws liquidity from an existing pool
/// todo: handle recent changes to config structur
contract RescueFromHookScript is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    HookManager public hookManager;

    function run() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        Config.ConfigData memory config = getConfigPerNetwork(chainId, pool_enum);
        // ModularHookV1 hook = ModularHookV1(address(0xccC7C10b872A9F449FA41Ef7a723ACB1615548C0));
        hookManager = HookManager(config.hookManager);
        ModularHookV1 hook = ModularHookV1(address(config.poolKey.hooks));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        rescueToken(Currency.unwrap(hook.token0()), address(config.poolKey.hooks));
        rescueToken(Currency.unwrap(hook.token1()), address(config.poolKey.hooks));
        rescueToken(hook.aToken0(), address(config.poolKey.hooks));
        rescueToken(hook.aToken1(), address(config.poolKey.hooks));
        vm.stopBroadcast();
    }

    function rescueToken(address token, address hook) internal {
        uint256 amountToRescue = IERC20(token).balanceOf(address(hook));
        if (amountToRescue == 0) {
            console.log("No tokens to rescue");
            return;
        }
        hookManager.rescue(hook, token, amountToRescue, receiver);
    }
}
