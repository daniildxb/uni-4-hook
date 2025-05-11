// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {HookManager} from "../src/HookManager.sol";
import {HookDeployer} from "../src/HookDeployer.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";

/// @notice Deploys HookManager and HookDeployer contracts
contract DeployPeripheryScript is Script, Deployers, Config {
    function run() external {
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        Config.ConfigData memory config = getConfigPerNetwork(chainId, pool_enum);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        HookManager hookManager = new HookManager(config.poolManager);
        HookDeployer hookDeployer = new HookDeployer(address(hookManager));
        hookManager.setHookDeployer(address(hookDeployer));

        vm.stopBroadcast();
    }
}
