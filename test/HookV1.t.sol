// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {HookV1} from "../src/HookV1.sol";

contract HookV1Test is Test {
    using CurrencyLibrary for Currency;

    function _deployHook(
        address poolManager,
        address token0,
        address token1,
        uint256 tickMin,
        uint256 tickMax,
        address aavePoolAddressProvider,
        string memory shareName,
        string memory shareSymbol
    ) internal returns (HookV1 hook) {
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs =
            abi.encode(poolManager, token0, token1, tickMin, tickMax, aavePoolAddressProvider, shareName, shareSymbol); //Add all the necessary constructor arguments from the hook
        deployCodeTo("HookV1.sol:HookV1", constructorArgs, flags);
        hook = HookV1(flags);
    }

    function test_construction() public {
        address poolManager = address(1);
        address token0 = address(2);
        address token1 = address(3);
        uint256 tickMin = 3000;
        uint256 tickMax = 60;
        address aavePoolAddressesProvider = address(4);
        string memory shareName = "name";
        string memory shareSymbol = "symbol";

        HookV1 hook = _deployHook(
            poolManager, token0, token1, tickMin, tickMax, aavePoolAddressesProvider, shareName, shareSymbol
        );

        PoolKey memory key =
            PoolKey(Currency.wrap(address(2)), Currency.wrap(address(3)), 3000, 60, IHooks(address(hook)));

        hook.addPool(key);
    }
}
