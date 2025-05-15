// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CustodyHook} from "./CustodyHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencySettler} from "v4-periphery/lib/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {Pool} from "v4-core/src/libraries/Pool.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {SwapMath} from "v4-core/src/libraries/SwapMath.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

/**
 * @title Base Hook
 * @notice Base contract for Uniswap V4 hooks that provides common functionality
 */
abstract contract SwapPricePreviewHook is CustodyHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;
    using SafeCast for *;
    using Pool for *;
    using ProtocolFeeLibrary for *;

    function _abs(int256 x) internal pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }

    function previewSwap(IPoolManager.SwapParams memory params)
        public
        view
        returns (BalanceDelta swapDelta, uint24 swapFee, Pool.SwapResult memory result)
    {
        // Scope variables to reduce stack usage
        {
            uint24 protocolFee;
            uint24 lpFee;
            // Get pool data
            (result.sqrtPriceX96, result.tick, protocolFee, lpFee) = poolManager.getSlot0(key.toId());

            // Set initial liquidity
            result.liquidity = uint128(totalAssets());

            // Calculate swap fee
            swapFee = protocolFee == 0 ? lpFee : uint16(protocolFee).calculateSwapFee(lpFee);
        }

        // amounts are negative here
        (int128 amount0, int128 amount1) = getTokenAmountsForLiquidity(result.liquidity);
        // check if we got enough of requested token to do the swap
        if (params.zeroForOne) {
            if (_abs(int256(amount0)) < _abs(params.amountSpecified)) {
                revert("Not enough token0");
            }
        } else {
            if (_abs(int256(amount1)) < _abs(params.amountSpecified)) {
                revert("Not enough token1");
            }
        }

        // Local computation scope
        {
            bool zeroForOne = params.zeroForOne;
            // the amount remaining to be swapped in/out of the input/output asset
            int256 amountSpecifiedRemaining = params.amountSpecified;
            // the amount swapped out/in of the output/input asset
            int256 amountCalculated = 0;

            // Create step computation struct
            Pool.StepComputations memory step;
            step.sqrtPriceStartX96 = result.sqrtPriceX96;

            // Compute swap step
            (result.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                result.sqrtPriceX96,
                SwapMath.getSqrtPriceTarget(zeroForOne, step.sqrtPriceNextX96, params.sqrtPriceLimitX96),
                result.liquidity,
                amountSpecifiedRemaining,
                swapFee
            );

            // Update remaining amounts based on exactInput/exactOutput
            if (params.amountSpecified > 0) {
                unchecked {
                    amountSpecifiedRemaining -= step.amountOut.toInt256();
                    amountCalculated -= (step.amountIn + step.feeAmount).toInt256();
                }
            } else {
                unchecked {
                    amountSpecifiedRemaining += (step.amountIn + step.feeAmount).toInt256();
                    amountCalculated += step.amountOut.toInt256();
                }
            }

            // Create final balance delta
            unchecked {
                if (zeroForOne != (params.amountSpecified < 0)) {
                    swapDelta = toBalanceDelta(
                        amountCalculated.toInt128(), (params.amountSpecified - amountSpecifiedRemaining).toInt128()
                    );
                } else {
                    swapDelta = toBalanceDelta(
                        (params.amountSpecified - amountSpecifiedRemaining).toInt128(), amountCalculated.toInt128()
                    );
                }
            }
        }
    }
}
