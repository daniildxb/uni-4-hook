// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHookDeployer} from "./HookDeployer.sol";
import {ModularHookV1HookConfig} from "./ModularHookV1.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

interface IHook {
    function addPool(PoolKey memory key) external;
}

contract HookManager {
    using PoolIdLibrary for PoolKey;

    event HookDeployed(address indexed hook, bytes32 indexed poolId, uint256 hookIndex, uint160 sqrtPriceX96);

    address public admin;
    address public poolManager;
    address public hookDeployer;

    mapping(bytes32 => address) public poolIdToHook;
    mapping(address => bytes32) public hookToPoolId;
    mapping(uint256 => address) public indexToHook;
    uint256 public hookCount = 0;

    constructor(address _poolManager) {
        poolManager = _poolManager;
        admin = msg.sender;
    }

    function setHookDeployer(address _hookDeployer) external {
        require(msg.sender == admin, "Only admin can set hook deployer");
        hookDeployer = _hookDeployer;
    }

    function deployHook(
        ModularHookV1HookConfig calldata hookParams,
        address expectedAddress,
        uint160 sqrtPriceX96,
        uint24 fee,
        int24 tickSpacing,
        bytes32 salt
    ) external {
        require(msg.sender == admin, "Only admin can deploy hooks");
        address hook = IHookDeployer(hookDeployer).deployHook(
            poolManager, hookParams, expectedAddress, salt
        );

        PoolKey memory key = PoolKey(hookParams.token0, hookParams.token1, fee, tickSpacing, IHooks(hook));
        IPoolManager(poolManager).initialize(key, sqrtPriceX96);
        // add pool
        IHook(hook).addPool(key);

        bytes32 poolId = PoolId.unwrap(key.toId());

        _storeHook(address(hook), poolId);
        emit HookDeployed(address(hook), poolId, hookCount, sqrtPriceX96);
        hookCount++;
    }

    function _storeHook(address hook, bytes32 poolId) internal {
        require(poolIdToHook[poolId] == address(0), "Hook already exists for this poolId");
        poolIdToHook[poolId] = hook;
        hookToPoolId[hook] = poolId;
        indexToHook[hookCount] = hook;
    }
}
