// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {HookV1Test} from "../unit/HookV1.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";


contract HookV1ForkTest is HookV1Test {
    function setUp() public virtual override {
        // set uniswap and aave contracts to use sepolia deployed ones
        manager = IPoolManager(address(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543));
        aavePoolAddressesProvider = address(0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A);
        // usdt
        token1 = Currency.wrap(address(0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0));
        // usdc
        token0 = Currency.wrap(address(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8));
        _deployHook();
        initPool(token0, token1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);
    }
}