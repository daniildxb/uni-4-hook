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
import {UniswapXExecutor} from "../src/swappers/UniswapXExecutor.sol";

/// @notice Withdraws liquidity from an existing pool
contract AddNewExecutor is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    HookManager public hookManager;

    function run() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        Config.ConfigData memory config = getConfigPerNetwork(chainId, pool_enum);

        // Access the hook manager from the config
        hookManager = HookManager(config.hookManager);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        UniswapXExecutor executor =
            new UniswapXExecutor(config.poolManager, config.reactor, filler, config.weth, address(hookManager));
        hookManager.addExecutor(address(executor));
        vm.stopBroadcast();
    }
}
