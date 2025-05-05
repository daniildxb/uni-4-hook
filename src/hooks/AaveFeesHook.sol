// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {AaveHook} from "./AaveHook.sol";
import {FeeTrackingHook} from "./FeeTrackingHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @title Modular Hook V1
 * @notice Combined hook implementing Aave integration, custody features, and fee tracking
 * Functionally equivalent to the original HookV1 but with modular architecture
 */
abstract contract AaveFeesHook is AaveHook, FeeTrackingHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using SafeCast for *;

    constructor(
        IPoolManager _poolManager,
        Currency _token0,
        Currency _token1,
        int24 _tickMin,
        int24 _tickMax,
        address _aavePoolAddressesProvider,
        string memory _shareName,
        string memory _shareSymbol
    )
        AaveHook(_poolManager, _token0, _token1, _tickMin, _tickMax, _aavePoolAddressesProvider, _shareName, _shareSymbol)
    {}

    function totalAssets() public view virtual override(AaveHook, ERC4626) returns (uint256) {
        return AaveHook.totalAssets();
    }

    function _transferFees(uint128 amount0, uint128 amount1, address treasury) internal virtual override {
        _withdrawFromAave(Currency.unwrap(token0), amount0, treasury);
        _withdrawFromAave(Currency.unwrap(token1), amount1, treasury);
    }

    function getUnclaimedFees() public view virtual override returns (int128 amount0, int128 amount1) {
        (amount0, amount1) = getTokenAmountsForLiquidity(unclaimedFees);
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

    function _beforeHookDeposit(uint256 amount0, uint256 amount1)
        internal
        virtual
        override
        trackFeesBefore
        setAssetsAfter
    {}

    function _beforeHookWithdrawal(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override
        trackFeesBefore
        setAssetsAfter
    {}
}
