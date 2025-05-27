// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {ModularHookV1, ModularHookV1HookConfig} from "src/ModularHookV1.sol";
import {HookManager} from "src/HookManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @notice Mines the address and deploys the ModularHookV1.sol Hook contract
/// used for non stable pairs
/// diff from stable script is - pricing, tick spacing, fee
contract DeployFullRangeScript is Script, Deployers, Config {
    using PoolIdLibrary for PoolKey;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        //  hook contracts must have specific flags encoded in the address
        Config.ConfigData memory config;
        {
            uint256 chainId = vm.envUint("CHAIN_ID");
            uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI
            config = getConfigPerNetwork(chainId, pool_enum);
        }
        uint160 price = 123606690699871326385319; // needs to be fetched ad hoc

        ModularHookV1HookConfig memory hookParams;
        {
            // Use a symmetric range around the adjusted price to ensure balanced liquidity
            int24 _tickMin = -887272;
            int24 _tickMax = 887272;
            string memory shareName = "LP";
            string memory shareSymbol = "LP";

            hookParams = ModularHookV1HookConfig({
                poolManager: IPoolManager(config.poolManager),
                token0: config.token0,
                token1: config.token1,
                tickMin: _tickMin,
                tickMax: _tickMax,
                aavePoolAddressesProvider: config.aavePoolAddressesProvider,
                shareName: shareName,
                shareSymbol: shareSymbol,
                fee_bps: 1000, // hook fee, not pool one 10%
                bufferSize0: 10e18, // 25 tokens with 18 decimals
                bufferSize1: 25e6, // 25 tokens with 6 decimals
                minTransferAmount0: 5e18, // 5 tokens with 6 decimals
                minTransferAmount1: 5e6 // 5 tokens with 6 decimals
            });
        }

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(hookParams);

        HookManager hookManager = HookManager(config.hookManager);
        // Move the mining and deployment into the run function where execution occurs
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144);
        bytes memory creationCode = abi.encodePacked(type(ModularHookV1).creationCode, constructorArgs);

        (address hookAddress, bytes32 salt) = HookMiner.find(address(hookManager), flags, creationCode, new bytes(0));

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        {
            uint24 fee = 100; // pool fee in mbps 10 = 0.001%
            int24 tickSpacing = 60;

            console.log("price", price);
            console.log("tick at price", TickMath.getTickAtSqrtPrice(price));
            console.log("expected  address", hookAddress);
            hookManager.deployHook(
                config.token0, config.token1, hookAddress, price, fee, tickSpacing, salt, creationCode
            );
        }
        vm.stopBroadcast();
        ModularHookV1 hook = ModularHookV1(hookAddress);
        (Currency currency0, Currency currency1, uint24 _fee, int24 _tickSpacing, IHooks hooks) = hook.key();
        PoolKey memory key =
            PoolKey({currency0: currency0, currency1: currency1, fee: _fee, tickSpacing: _tickSpacing, hooks: hooks});
        console.log(vm.toString(PoolId.unwrap(key.toId())));
    }
}
