// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {HotBufferHook} from "./HotBufferHook.sol";
import {AaveHook} from "./AaveHook.sol";
import {ExtendedHook} from "./ExtendedHook.sol";
import {CustodyHook} from "./CustodyHook.sol";
import {FeeTrackingHook} from "./FeeTrackingHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

/**
 * @title Contract that integrates Aave Hook with Fee Tracking Hook
 * @notice lifecycle hooks for Hook Deposits are defined empty as neither contract in
 * the inheritance chain implements them and we need to add modifiers for potential changes
 */
abstract contract AaveFeesHook is HotBufferHook, FeeTrackingHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using SafeCast for *;

    function totalAssets() public view virtual override(AaveHook, FeeTrackingHook) returns (uint256) {
        uint256 _totalAssets = AaveHook.totalAssets();
        if (unclaimedFees > _totalAssets) {
            return 0;
        }
        return AaveHook.totalAssets() - unclaimedFees;
    }

    function getUnclaimedFees() public view virtual override returns (int128 amount0, int128 amount1) {
        (amount0, amount1) = getTokenAmountsForLiquidity(unclaimedFees);
    }

    function _transferFees(uint128 amount0, uint128 amount1, address treasury)
        internal
        virtual
        override(HotBufferHook, FeeTrackingHook)
    {
        return HotBufferHook._transferFees(amount0, amount1, treasury);
    }

    // not using setAssetsAfter as it will be done in the _afterSwap
    function _beforeSwap(
        address sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata swapParams,
        bytes calldata hookData
    ) internal virtual override(AaveHook, BaseHook) trackFeesBefore returns (bytes4, BeforeSwapDelta, uint24) {
        return AaveHook._beforeSwap(sender, _key, swapParams, hookData);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    )
        internal
        virtual
        override(AaveHook, BaseHook)
        trackFeesBefore
        setAssetsAfter
        returns (bytes4 selector, int128 hookDelta)
    {
        return AaveHook._afterSwap(sender, _key, swapParams, delta, hookData);
    }

    function _beforeHookDeposit(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override
        trackFeesBefore
    {
        super._beforeHookDeposit(amount0, amount1, receiver);
    }

    function _afterHookDeposit(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override(CustodyHook, HotBufferHook)
        setAssetsAfter
    {
        super._afterHookDeposit(amount0, amount1, receiver);
    }

    function _beforeHookWithdrawal(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override
        trackFeesBefore
    {
        super._beforeHookWithdrawal(amount0, amount1, receiver);
    }

    function _afterHookWithdrawal(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override(CustodyHook, HotBufferHook)
        setAssetsAfter
    {
        super._afterHookWithdrawal(amount0, amount1, receiver);
    }

    function _beforeInitialize(address sender, PoolKey calldata poolKey, uint160 sqrtPriceX96)
        internal
        virtual
        override(AaveHook, ExtendedHook)
        returns (bytes4)
    {
        return AaveHook._beforeInitialize(sender, poolKey, sqrtPriceX96);
    }
}
