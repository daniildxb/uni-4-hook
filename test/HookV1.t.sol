// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";


import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {HookV1} from "../src/HookV1.sol";

contract HookV1Test is Test, Deployers {
    using CurrencyLibrary for Currency;

    address poolManager = address(1);
    Currency token0;
    Currency token1;
    uint256 tickMin = 3000;
    uint256 tickMax = 60;
    address aavePoolAddressesProvider = address(4);
    string shareName = "name";
    string shareSymbol = "symbol";
    HookV1 hook;


    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    function setUp() public {
        deployFreshManagerAndRouters();
        (token0, token1) = deployMintAndApprove2Currencies();
        _deployHook();

        (simpleKey, simplePoolId) = initPool(token0, token1, IHooks(hook), 3000, SQRT_PRICE_1_1);
        hook.addPool(simpleKey);
    }


    function _deployHook() internal {
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs =
            abi.encode(poolManager, token0, token1, tickMin, tickMax, aavePoolAddressesProvider, shareName, shareSymbol); //Add all the necessary constructor arguments from the hook
        deployCodeTo("HookV1.sol:HookV1", constructorArgs, flags);
        hook = HookV1(flags);
    }

    function test_construction() public {
        console.log("hook: ", address(hook));
        assertNotEq(address(hook), address(0));
    }

    // function test_addLiquidity() public {
    //     address poolManager = address(1);
    //     address token0 = address(2);
    //     address token1 = address(3);
    //     uint256 tickMin = 3000;
    //     uint256 tickMax = 60;
    //     address aavePoolAddressesProvider = address(4);
    //     string memory shareName = "name";
    //     string memory shareSymbol = "symbol";

    //     (HookV1 hook, PoolKey memory key) = _deployHook(
    //         poolManager, token0, token1, tickMin, tickMax, aavePoolAddressesProvider, shareName, shareSymbol
    //     );

    //     // IPoolManager(poolManager).addLiquidity(key, 100, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, "");
    // }
}
