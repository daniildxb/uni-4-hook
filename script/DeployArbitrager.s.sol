// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {UniswapArbitrager} from "../src/swappers/UniswapArbitrager.sol";
import {SwapRouterNoChecks} from "v4-core/src/test/SwapRouterNoChecks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/// @notice Mines the address and deploys the ModularHookV1.sol Hook contract
/// used for non stable pairs
/// diff from stable script is - pricing, tick spacing, fee
contract DeployArbitrager is Script, Deployers, Config {
    address _swapRouterAddress;

    function run() external {
        Config.ConfigData memory config;
        {
            uint256 chainId = vm.envUint("CHAIN_ID");
            uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI
            config = getConfigPerNetwork(chainId, pool_enum);
        }
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        PoolKey memory uniPoolKey = PoolKey({
            currency0: config.poolKey.currency0,
            currency1: config.poolKey.currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(0x0000000000000000000000000000000000000000)
        });

        // SwapRouterNoChecks routerNoChecks = new SwapRouterNoChecks(IPoolManager(config.poolManager));
        address routerNoChecks = 0x4400ad88f0Cd547f0BC3C279dC2b64A91a98F161; // base

        new UniswapArbitrager(config.poolManager, filler, filler, address(routerNoChecks), config.poolKey, uniPoolKey);
        vm.stopBroadcast();
    }
}
