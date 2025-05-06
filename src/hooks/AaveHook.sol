// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CustodyHook} from "./CustodyHook.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPoolAddressesProvider.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/**
 * @title Aave Hook
 * @notice Hook that integrates with Aave lending protocol
 */
abstract contract AaveHook is CustodyHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    IPoolAddressesProvider public aavePoolAddressesProvider;
    address public aToken0;
    address public aToken1;

    event MoneyMarkeyDeposit(uint256 amount0, uint256 amount1, uint256 liquidityAmount);
    event MoneyMarkeyWithdrawal(uint256 amount0, uint256 amount1, uint256 liquidityAmount);

    constructor(
        IPoolManager _poolManager,
        Currency _token0,
        Currency _token1,
        int24 _tickMin,
        int24 _tickMax,
        address _aavePoolAddressesProvider,
        string memory _shareName,
        string memory _shareSymbol
    ) CustodyHook(_poolManager, _token0, _token1, _tickMin, _tickMax, _shareName, _shareSymbol) {
        aavePoolAddressesProvider = IPoolAddressesProvider(_aavePoolAddressesProvider);
        aToken0 = IPool(aavePoolAddressesProvider.getPool()).getReserveData(Currency.unwrap(token0)).aTokenAddress;
        aToken1 = IPool(aavePoolAddressesProvider.getPool()).getReserveData(Currency.unwrap(token1)).aTokenAddress;
    }

    /**
     * @dev Returns the total assets held by the hook, using aToken balances
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 token0Balance = IERC20(aToken0).balanceOf(address(this));
        uint256 token1Balance = IERC20(aToken1).balanceOf(address(this));

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickMin),
            TickMath.getSqrtPriceAtTick(tickMax),
            token0Balance,
            token1Balance
        );
        return uint256(liquidityDelta);
    }

    /**
     * @dev Deposits tokens to Aave protocol
     * @param token The token address to deposit
     * @param amount The amount to deposit
     */
    function _depositToAave(address token, uint256 amount) internal {
        IERC20(token).forceApprove(aavePoolAddressesProvider.getPool(), amount);
        IPool(aavePoolAddressesProvider.getPool()).supply(token, amount, address(this), 0);
    }

    /**
     * @dev Withdraws tokens from Aave protocol
     * @param token The token address to withdraw
     * @param amount The amount to withdraw
     * @param receiver The address to receive the withdrawn tokens
     */
    function _withdrawFromAave(address token, uint256 amount, address receiver) internal returns (uint256) {
        return IPool(aavePoolAddressesProvider.getPool()).withdraw(token, amount, receiver);
    }

    /**
     * @dev Before swap hook that takes tokens from Aave and adds liquidity to the pool
     */
    function _beforeSwap(address sender, PoolKey calldata _key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Fetch token balances and put them into liquidity
        uint256 liquidityDelta = totalAssets();

        uint256 amount0 = _withdrawFromAave(Currency.unwrap(token0), type(uint256).max, address(this));
        uint256 amount1 = _withdrawFromAave(Currency.unwrap(token1), type(uint256).max, address(this));

        emit MoneyMarkeyWithdrawal(amount0, amount1, liquidityDelta);

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickMin,
            tickUpper: tickMax,
            liquidityDelta: liquidityDelta.toInt256(),
            salt: 0
        });

        (BalanceDelta delta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(key, params, abi.encode(0));

        // transfer tokens to the poolManager
        // todo: maybe we don't need to actually call settle...
        poolManager.sync(key.currency0);
        IERC20(Currency.unwrap(key.currency0)).safeTransfer(address(poolManager), uint256(int256(-delta.amount0())));
        poolManager.settle();

        poolManager.sync(key.currency1);
        IERC20(Currency.unwrap(key.currency1)).safeTransfer(address(poolManager), uint256(int256(-delta.amount1())));
        poolManager.settle();
        // for some reason currency settler fails with USDT
        // CurrencySettler.settle(key.currency0, poolManager, address(this), uint256(int256(-delta.amount0())), false);
        // CurrencySettler.settle(key.currency1, poolManager, address(this), uint256(int256(-delta.amount1())), false);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /**
     * @dev After swap hook that withdraws liquidity from the pool and deposits it back to Aave
     */
    function _afterSwap(address, PoolKey calldata _key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, int128)
    {
        // Fetch existing liquidity
        // Withdraw liquidity from PoolManager
        uint128 liquidity = poolManager.getLiquidity(key.toId());

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickMin,
            tickUpper: tickMax,
            liquidityDelta: int256(-int128(liquidity)),
            salt: 0
        });

        (BalanceDelta delta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(key, params, abi.encode(0));

        // Take tokens from pool manager
        poolManager.take(token0, address(this), uint256(int256(delta.amount0())));
        poolManager.take(token1, address(this), uint256(int256(delta.amount1())));

        // Deposit to Aave
        uint256 amount0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(this));
        uint256 amount1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));
        _depositToAave(Currency.unwrap(key.currency0), amount0);
        _depositToAave(Currency.unwrap(key.currency1), amount1);
        emit MoneyMarkeyDeposit(amount0, amount1, totalAssets());

        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @dev Implementation of the deposit processing for CustodyHook
     * Deposits tokens to Aave
     */
    function _afterHookDeposit(uint256 amount0, uint256 amount1) internal virtual override {
        _depositToAave(Currency.unwrap(key.currency0), amount0);
        _depositToAave(Currency.unwrap(key.currency1), amount1);
    }

    /**
     * @dev Implementation of the withdrawal processing for CustodyHook
     * Withdraws tokens from Aave and sends them to the receiver
     */
    function _afterHookWithdrawal(uint256 amount0, uint256 amount1, address receiver) internal virtual override {
        _withdrawFromAave(Currency.unwrap(key.currency0), amount0, receiver);
        _withdrawFromAave(Currency.unwrap(key.currency1), amount1, receiver);
    }
}
