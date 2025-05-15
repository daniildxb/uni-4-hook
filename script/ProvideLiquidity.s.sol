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

/// @notice Provides liquidity to an existing pool
contract ProvideLiquidityScript is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    function run() public {
        // usdc
        uint256 maxTokenAmount0 = 8 * 1e18;
        uint256 maxTokenAmount1 = 8 * 1e6;
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        Config.ConfigData memory config = getConfigPerNetwork(chainId, pool_enum);
        ModularHookV1 hook = ModularHookV1(address(config.poolKey.hooks));
        (uint128 liquidity, int128 amount0, int128 amount1) =
            hook.getLiquidityForTokenAmounts(maxTokenAmount0, maxTokenAmount1);
        // Provide liquidity to the pool
        console.log("amount0", amount0);
        console.log("amount1", amount1);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        console.log("1");
        IERC20(Currency.unwrap(hook.token0())).forceApprove(address(hook), 100 * 1e18);
        console.log("2");
        IERC20(Currency.unwrap(hook.token1())).forceApprove(address(hook), 100 * 1e18);
        console.log("liquidity", uint256(liquidity));
        hook.deposit(uint256(liquidity), receiver);

        // hook.moveLiquidityToPool();
        vm.stopBroadcast();
    }
}
