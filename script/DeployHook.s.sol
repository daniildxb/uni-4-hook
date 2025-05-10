// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Config} from "./base/Config.sol";

/// @notice Mines the address and deploys the ModularHookV1.sol Hook contract
contract DeployScript is Script, Deployers, Config {
    using PoolIdLibrary for PoolKey;

    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        //  hook contracts must have specific flags encoded in the address
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144);

        uint256 chainId = vm.envUint("CHAIN_ID");

        Config.ConfigData memory config = getConfigPerNetwork(chainId);
        // @note we need to pass those in an order
        // 60 / -60 corresponds to price range
        // "1.006017734268818165222506292999135"
        // "0.994018262239490337401066230369517"
        int24 _tickMin = -2; // 2 bips away from 1:1
        int24 _tickMax = 2;
        string memory shareName = "LP";
        string memory shareSymbol = "LP";

        ModularHookV1.HookConfig memory hookParams = ModularHookV1.HookConfig({
            poolManager: IPoolManager(config.poolManager),
            token0: config.token0,
            token1: config.token1,
            tickMin: _tickMin,
            tickMax: _tickMax,
            aavePoolAddressesProvider: config.aavePoolAddressesProvider,
            shareName: shareName,
            shareSymbol: shareSymbol,
            feeCollector: address(0x1),
            fee_bps: 1000, // 10%
            bufferSize: 1e7,
            minTransferAmount: 1e6
        });

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(hookParams);

        // Move the mining and deployment into the run function where execution occurs
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(ModularHookV1).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        ModularHookV1 hook = new ModularHookV1{salt: salt}(hookParams);

        require(address(hook) == hookAddress, "HookV1: hook address mismatch");

        // create pool
        uint24 fee = 10;

        PoolKey memory key = PoolKey(config.token0, config.token1, fee, 1, IHooks(hook));
        PoolId id = key.toId();
        IPoolManager(config.poolManager).initialize(key, SQRT_PRICE_1_1);
        // add pool
        hook.addPool(key);
        console.log(vm.toString(PoolId.unwrap(id)));
        vm.stopBroadcast();
    }
}
