// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {UniswapArbitrager} from "../../../src/swappers/UniswapArbitrager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SwapRouterNoChecks} from "v4-core/src/test/SwapRouterNoChecks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract ArbitragerTest is BaseTest {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    UniswapArbitrager arbitrager;
    PoolKey yfPoolKey; // YieldFusion pool (less liquidity)
    PoolKey uniPoolKey; // Uniswap pool (more liquidity)
    PoolId yfPoolId;
    PoolId uniPoolId;
    SwapRouterNoChecks arbitrageSwapRouter;

    address swapper = address(0x123);
    uint24 yfFee = 500; // 0.05% fee for YF pool
    uint24 uniFee = 3000; // 0.3% fee for Uni pool
    int24 yfTickSpacing = 60; // Same as uni for simplicity
    int24 uniTickSpacing = 60; // Standard tick spacing

    function setUp() public virtual override {
        super.setUp();

        // Deploy swap router
        arbitrageSwapRouter = new SwapRouterNoChecks(manager);

        // Use the existing hook pool as one of the pools (has liquidity already)
        yfPoolKey = simpleKey; // Use the existing hook-managed pool as YF pool

        // Create a second pool without hooks (Uniswap pool with more liquidity)
        uniPoolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: uniFee,
            tickSpacing: uniTickSpacing,
            hooks: IHooks(address(0)) // No hooks for simplicity
        });

        yfPoolId = yfPoolKey.toId();
        uniPoolId = uniPoolKey.toId();

        // Initialize the second pool (YF pool already initialized in BaseTest)
        manager.initialize(uniPoolKey, SQRT_PRICE_1_2);

        // The hook pool already has liquidity from BaseTest depositTokensToHook
        // Just add liquidity to the second pool
        _addLiquidityToPool(uniPoolKey, 5000e10); // Larger liquidity for Uni pool

        // Deploy arbitrager contract
        arbitrager = new UniswapArbitrager(
            address(manager),
            swapper,
            address(this), // owner
            address(arbitrageSwapRouter),
            yfPoolKey,
            uniPoolKey
        );

        // Fund the swapper account with tokens for testing
        deal(Currency.unwrap(token0), swapper, 10000e6);
        deal(Currency.unwrap(token1), swapper, 10000e6);

        // Approve arbitrager to spend swapper's tokens
        vm.startPrank(swapper);
        MockERC20(Currency.unwrap(token0)).approve(address(manager), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(manager), type(uint256).max);
        vm.stopPrank();
    }

    function _addLiquidityToPool(PoolKey memory key, uint256 liquidityAmount) internal {
        // Give this contract tokens to add liquidity
        deal(Currency.unwrap(token0), address(this), liquidityAmount * 1000);
        deal(Currency.unwrap(token1), address(this), liquidityAmount * 1000);

        // Approve tokens for the modify liquidity router
        MockERC20(Currency.unwrap(token0)).approve(address(modifyLiquidityRouter), liquidityAmount * 1000);
        MockERC20(Currency.unwrap(token1)).approve(address(modifyLiquidityRouter), liquidityAmount * 1000);

        // Add liquidity with appropriate amounts based on the pool
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -887220,
                tickUpper: 887220,
                liquidityDelta: int256(liquidityAmount), // Use the actual liquidity amount
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function testArbitragerDeployment() public {
        // Test basic deployment and configuration
        assertNotEq(address(arbitrager), address(0), "Arbitrager should be deployed");
        assertEq(address(arbitrager.manager()), address(manager), "Manager should be set correctly");
    }

    function testArbitrageYfToUni_ZeroForOne() public {
        // Test arbitrage from YF pool to Uni pool, swapping token0 for token1
        // Use a small amount relative to total liquidity (1% of liquidity)
        uint256 swapAmount = 5e6; // 5 tokens (much smaller than 500 total liquidity)

        // Get initial balances
        uint256 initialToken0 = MockERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 initialToken1 = MockERC20(Currency.unwrap(token1)).balanceOf(swapper);

        console.log("Initial token0:", initialToken0);
        console.log("Initial token1:", initialToken1);
        console.log("Swap amount:", swapAmount);

        // Execute arbitrage: YF -> Uni, token0 -> token1
        vm.prank(swapper);
        uint256 profit = arbitrager.swap(true, true, swapAmount);

        // Get final balances
        uint256 finalToken0 = MockERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 finalToken1 = MockERC20(Currency.unwrap(token1)).balanceOf(swapper);

        console.log("Final token0:", finalToken0);
        console.log("Final token1:", finalToken1);
        console.log("Profit:", profit);

        // For now, profit calculation is not implemented, so it returns 0
        assertGt(finalToken0, initialToken0, "token 0 should increase");
        assertEq(finalToken1, initialToken1, "token 1 should stay the same");
        assertEq(profit, finalToken0 - initialToken0, "Profit should match");
    }

    function testArbitrageUniToYf_OneForZero() public {
        // Test arbitrage from Uni pool to YF pool, swapping token1 for token0
        uint256 swapAmount = 5e6; // 5 tokens

        // Get initial balances
        uint256 initialToken0 = MockERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 initialToken1 = MockERC20(Currency.unwrap(token1)).balanceOf(swapper);

        // Execute arbitrage: Uni -> YF, token1 -> token0
        vm.prank(swapper);
        uint256 profit = arbitrager.swap(false, false, swapAmount);

        // Get final balances
        uint256 finalToken0 = MockERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 finalToken1 = MockERC20(Currency.unwrap(token1)).balanceOf(swapper);

        // Verify that token1 decreased (spent in first swap)
        assertGt(finalToken1, initialToken1, "Token1 should increase");
        assertEq(finalToken0, initialToken0, "Token1 should stay the same");

        // For now, profit calculation is not implemented, so it returns 0
        assertEq(profit, finalToken1 - initialToken1, "Profit should match");
    }

    function testOnlySwapperCanExecute() public {
        uint256 swapAmount = 5e6;

        // Test that non-swapper addresses cannot execute arbitrage
        vm.prank(user1);
        vm.expectRevert("not allowed");
        arbitrager.swap(true, true, swapAmount);

        // Test that swapper can execute arbitrage
        vm.prank(swapper);
        arbitrager.swap(true, true, swapAmount);
    }
}
