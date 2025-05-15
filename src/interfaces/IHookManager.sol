// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "v4-core/src/types/Currency.sol";


interface IHookManager {
    event HookDeployed(address indexed hook, bytes32 indexed poolId, uint256 hookIndex, uint160 sqrtPriceX96);

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

    function getAllHooks() external view returns (address[] memory);
}
