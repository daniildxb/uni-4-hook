// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {HookV1Test} from "../unit/HookV1.t.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {SwapRouterNoChecks} from "v4-core/src/test/SwapRouterNoChecks.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolModifyLiquidityTestNoChecks} from "v4-core/src/test/PoolModifyLiquidityTestNoChecks.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {PoolNestedActionsTest} from "v4-core/src/test/PoolNestedActionsTest.sol";
import {ActionsRouter} from "v4-core/src/test/ActionsRouter.sol";

contract HookV1ForkTest is HookV1Test {
    function setUp() public virtual override {
        // set uniswap and aave contracts to use mainnet deployed ones
        manager = IPoolManager(address(0x000000000004444c5dc75cB358380D2e3dE08A90));
        aavePoolAddressesProvider = address(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
        // usdt
        token1 = Currency.wrap(address(0xdAC17F958D2ee523a2206206994597C13D831ec7));
        // usdc
        token0 = Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
        _deployHook(token0, token1);
        (simpleKey, simplePoolId) = initPool(token0, token1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);

        deal(Currency.unwrap(token0), address(this), 1000, false);
        deal(Currency.unwrap(token1), address(this), 1000, false);
        _deployPeriphery();
    }

    function _deployPeriphery() internal {
        swapRouter = new PoolSwapTest(manager);
        swapRouterNoChecks = new SwapRouterNoChecks(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        claimsRouter = new PoolClaimsTest(manager);
        nestedActionRouter = new PoolNestedActionsTest(manager);
        feeController = makeAddr("feeController");
        actionsRouter = new ActionsRouter(manager);
    }
}
