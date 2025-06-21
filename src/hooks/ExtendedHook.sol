// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolIdLibrary, PoolId} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencySettler} from "v4-periphery/lib/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IModularHook} from "../interfaces/IModularHook.sol";

/**
 * @title Base Hook
 * @notice Base contract for Uniswap V4 hooks that provides common functionality
 */
abstract contract ExtendedHook is IModularHook, BaseHook {
    event Deposit(
        address indexed sender, address indexed owner, uint256 assets0, uint256 assets1, uint256 shares, bytes referral
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets0,
        uint256 assets1,
        uint256 shares
    );

    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;
    using SafeCast for *;

    int24 public tickMin;
    int24 public tickMax;
    Currency public token0;
    Currency public token1;
    bool public liquidityInitialized;
    PoolKey public key;

    constructor(IPoolManager _poolManager, Currency _token0, Currency _token1, int24 _tickMin, int24 _tickMax)
        BaseHook(_poolManager)
    {
        token0 = _token0;
        token1 = _token1;
        tickMin = _tickMin;
        tickMax = _tickMax;
    }

    // Add a pool to be managed by this hook
    function addPool(PoolKey calldata _key) public {
        assert(_key.currency0 == token0);
        assert(_key.currency1 == token1);
        // verifies that the pool is not already added
        assert(address(key.hooks) == address(0));
        // verifies pool uses this hook
        assert(address(_key.hooks) == address(this));
        key = _key;
    }

    // VIEWS

    function getSlot0() public view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
        return poolManager.getSlot0(key.toId());
    }

    function getPoolId() public view returns (bytes32) {
        return PoolId.unwrap(key.toId());
    }

    function getHookTokens() public view returns (address, address) {
        return (Currency.unwrap(token0), Currency.unwrap(token1));
    }

    // returns negative values!!
    function getTokenAmountsForLiquidity(uint256 liqudity) public view returns (int128 amount0, int128 amount1) {
        BalanceDelta delta = getPoolDelta(liqudity.toInt128());
        return (delta.amount0(), delta.amount1());
    }

    function getLiquidityForTokenAmounts(uint256 _amount0, uint256 _amount1)
        public
        view
        returns (uint128 liquidity, int128 amount0, int128 amount1)
    {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(key.toId());
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickMin), TickMath.getSqrtPriceAtTick(tickMax), _amount0, _amount1
        );

        BalanceDelta delta = getPoolDelta(liquidity.toInt128());
        amount0 = delta.amount0();
        amount1 = delta.amount1();
    }

    function getTokenAmountsFromDelta(BalanceDelta delta) public view returns (int128 amount0, int128 amount1) {
        return (delta.amount0(), delta.amount1());
    }

    // Some black magic copied from the Pool.sol::modifyLiquidity()
    function getPoolDelta(int128 liquidityDelta) public view returns (BalanceDelta delta) {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(key.toId());
        if (tick < tickMin) {
            // current tick is below the passed range; liquidity can only become in range by crossing from left to
            // right, when we'll need _more_ currency0 (it's becoming more valuable) so user must provide it
            delta = toBalanceDelta(
                SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtPriceAtTick(tickMin), TickMath.getSqrtPriceAtTick(tickMax), liquidityDelta
                ).toInt128(),
                0
            );
        } else if (tick < tickMax) {
            delta = toBalanceDelta(
                SqrtPriceMath.getAmount0Delta(sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickMax), liquidityDelta)
                    .toInt128(),
                SqrtPriceMath.getAmount1Delta(TickMath.getSqrtPriceAtTick(tickMin), sqrtPriceX96, liquidityDelta)
                    .toInt128()
            );
        } else {
            // current tick is above the passed range; liquidity can only become in range by crossing from right to
            // left, when we'll need _more_ currency1 (it's becoming more valuable) so user must provide it
            delta = toBalanceDelta(
                0,
                SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtPriceAtTick(tickMin), TickMath.getSqrtPriceAtTick(tickMax), liquidityDelta
                ).toInt128()
            );
        }
    }
}
