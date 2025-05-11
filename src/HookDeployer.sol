// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {ModularHookV1, ModularHookV1HookConfig} from "./ModularHookV1.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

interface IHookDeployer {
    event HookDeployed(address indexed hook, bytes32 indexed poolId, uint256 hookIndex);

    function deployHook(
        address poolManager,
        ModularHookV1HookConfig calldata hookParams,
        address expectedAddress,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        bytes32 salt
    ) external returns (address hookAddress, bytes32 poolId);
}

contract HookDeployer is IHookDeployer {
    using PoolIdLibrary for PoolKey;

    address public hookManagerAddress;

    constructor(address _hookManagerAddress) {
        hookManagerAddress = _hookManagerAddress;
    }

    function deployHook(
        address poolManager,
        ModularHookV1HookConfig calldata hookParams,
        address expectedAddress,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        bytes32 salt
    ) external returns (address hookAddress, bytes32 poolId) {
        require(msg.sender == hookManagerAddress, "Only hook manager can deploy hooks");
        ModularHookV1 hook = new ModularHookV1{salt: salt}(hookParams);
        require(address(hook) == expectedAddress, "HookV1: hook address mismatch");

        PoolKey memory key = PoolKey(hookParams.token0, hookParams.token1, fee, tickSpacing, IHooks(hook));
        PoolId id = key.toId();
        console.log("initializing pool");
        IPoolManager(poolManager).initialize(key, sqrtPriceX96);
        // add pool
        console.log("Adding pool to hook");
        hook.addPool(key);
        console.log("Pool added to hook");
        hookAddress = address(hook);
        poolId = PoolId.unwrap(id);
    }
}
