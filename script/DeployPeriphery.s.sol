// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {HookManager} from "../src/HookManager.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";
import {UniswapXExecutor} from "../src/swappers/UniswapXExecutor.sol";

/// @notice Deploys HookManager
contract DeployPeripheryScript is Script, Deployers, Config {
    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        Config.ConfigData memory config = getConfigPerNetwork(chainId, pool_enum);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // Deploy the simplified HookManager that handles deployment directly
        HookManager hookManager = new HookManager(config.poolManager, receiver);
        UniswapXExecutor executor =
            new UniswapXExecutor(config.poolManager, config.reactor, filler, config.weth, address(hookManager));

        hookManager.addExecutor(address(executor));
        vm.stopBroadcast();

        // Log the address
        console.log("HookManager deployed at:", address(hookManager));
        console.log("UniswapXExecutor deployed at:", address(executor));
    }
}
