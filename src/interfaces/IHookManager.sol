// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";

interface IHookManager {
    event HookDeployed(address indexed hook, PoolId indexed poolId, uint256 hookIndex, uint160 sqrtPriceX96);
    event ExecutorAdded(address indexed executor, uint256 executorIndex);
    event DepositCapSet(address indexed hook, uint256 depositCap0, uint256 depositCap1);
    event AllowlistFlipped(address indexed hook, bool allowlistState);
    event FeeBpsUpdated(address indexed hook, uint256 feeBps);
    event FeesCollected(address indexed hook);

    /**
     * @notice Deploys a ModularHookV1 hook with CREATE2 and initializes it
     * @param token0 The first currency for the pool
     * @param token1 The second currency for the pool
     * @param expectedAddress The expected address of the hook (for verification)
     * @param sqrtPriceX96 The initial sqrt price for the pool
     * @param fee The fee tier for the pool
     * @param tickSpacing The tick spacing for the pool
     * @param salt The salt for CREATE2 deployment
     * @param creationCode The creation bytecode of the hook with constructor args
     */
    function deployHook(
        Currency token0,
        Currency token1,
        address expectedAddress,
        uint160 sqrtPriceX96,
        uint24 fee,
        int24 tickSpacing,
        bytes32 salt,
        bytes calldata creationCode
    ) external;

    /**
     * @notice Returns the address of the hook for a given poolId
     * @param executor address of the exucutor
     */
    function addExecutor(address executor) external;

    /**
     * @notice Returns the addresses all hooks
     * @return The addresses of the hook
     */
    function getAllHooks() external view returns (address[] memory);
}
