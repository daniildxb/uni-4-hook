// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {MockAToken} from "./utils/mocks/MockAToken.sol";
import {MockAavePool} from "./utils/mocks/MockAavePool.sol";
import {MockAavePoolAddressesProvider} from "./utils/mocks/MockAavePoolAddressesProvider.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// Import the modular hook instead of the original HookV1
import {ModularHookV1} from "../src/ModularHookV1.sol";

contract BaseTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency token0;
    Currency token1;
    // todo: update to use 60 / -60 ticks an 0.01% fee
    int24 tickMin = -3000;
    int24 tickMax = 3000;
    address aavePoolAddressesProvider;
    string shareName = "name";
    string shareSymbol = "symbol";
    ModularHookV1 hook; // Changed from HookV1 to ModularHookV1
    uint24 fee = 3000;
    uint256 fee_bps = 1000; // 10%
    uint256 bufferSize = 1e7;
    uint256 minTransferAmount = 1e6;
    address feeCollector = address(0x1);
    address admin = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);

    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    function setUp() public virtual {
        console.log("1");
        deployFreshManagerAndRouters();
        (token0, token1) = deployMintAndApprove2Currencies();

        console.log("2");
        MockAToken aToken0 = new MockAToken(Currency.unwrap(token0), "aToken0", "aToken0");
        console.log("3");
        MockAToken atoken1 = new MockAToken(Currency.unwrap(token1), "aToken1", "aToken1");

        console.log("4");
        MockAavePool aavePool = new MockAavePool(Currency.unwrap(token0), aToken0, Currency.unwrap(token1), atoken1);
        console.log("5");
        aavePoolAddressesProvider = address(new MockAavePoolAddressesProvider(address(aavePool)));

        console.log("6");
        _deployHook();

        console.log("7");
        (simpleKey, simplePoolId) = initPool(token0, token1, IHooks(hook), 3000, SQRT_PRICE_1_1);
        console.log("8");
        hook.addPool(simpleKey);
    }

    function _deployHook() internal virtual {
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        ModularHookV1.HookConfig memory hookParams = ModularHookV1.HookConfig({
            poolManager: IPoolManager(manager),
            token0: token0,
            token1: token1,
            tickMin: tickMin,
            tickMax: tickMax,
            aavePoolAddressesProvider: aavePoolAddressesProvider,
            shareName: shareName,
            shareSymbol: shareSymbol,
            feeCollector: feeCollector,
            fee_bps: fee_bps,
            bufferSize: bufferSize,
            minTransferAmount: minTransferAmount
        });
        bytes memory constructorArgs = abi.encode(hookParams); //Add all the necessary constructor arguments from the hook
        deployCodeTo("ModularHookV1.sol:ModularHookV1", constructorArgs, flags); // Changed from HookV1 to ModularHookV1
        hook = ModularHookV1(flags); // Changed from HookV1 to ModularHookV1
    }
}
