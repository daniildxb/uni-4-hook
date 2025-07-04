// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {AaveFeesHook} from "./hooks/AaveFeesHook.sol";
import {RescueHook} from "./hooks/RescueHook.sol";
import {DonationHook} from "./hooks/DonationHook.sol";
import {RolesHook} from "./hooks/RolesHook.sol";
import {CustodyHook} from "./hooks/CustodyHook.sol";
import {AllowlistedHook} from "./hooks/AllowlistedHook.sol";
import {DepositCapHook} from "./hooks/DepositCapHook.sol";
import {AaveHook} from "./hooks/AaveHook.sol";
import {ExtendedHook} from "./hooks/ExtendedHook.sol";
import {HotBufferHook} from "./hooks/HotBufferHook.sol";
import {FeeTrackingHook} from "./hooks/FeeTrackingHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

struct ModularHookV1HookConfig {
    IPoolManager poolManager;
    int24 tickMin;
    int24 tickMax;
    address aavePoolAddressesProvider;
    string shareName;
    string shareSymbol;
    uint256 fee_bps;
    uint256 bufferSize0;
    uint256 bufferSize1;
    uint256 minTransferAmount0;
    uint256 minTransferAmount1;
}

/**
 * @title Modular Hook V1
 * @notice Most of the functionality is inherited, only defines permissions
 * and overrides for abstract methods
 */
contract ModularHookV1 is DepositCapHook, RescueHook, DonationHook, AaveFeesHook, AllowlistedHook {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20Metadata;

    constructor(ModularHookV1HookConfig memory config)
        RolesHook(msg.sender)
        AaveHook(config.aavePoolAddressesProvider)
        HotBufferHook(config.bufferSize0, config.bufferSize1, config.minTransferAmount0, config.minTransferAmount1)
        ExtendedHook(config.poolManager, config.tickMin, config.tickMax)
        FeeTrackingHook(config.fee_bps)
        // actual asset is liquidity value from the pool, not token
        ERC4626(IERC20Metadata(address(0)))
        ERC20(config.shareName, config.shareSymbol)
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true, // <----
            afterInitialize: false,
            beforeAddLiquidity: true, // <----
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true, // <----
            afterSwap: true, // <----
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // overrides of methods defined in multiple contracts
    // todo: check if we can just call super instead of AaveFeesHook
    function totalAssets() public view virtual override(AaveFeesHook, ERC4626) returns (uint256) {
        return AaveFeesHook.totalAssets();
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata swapParams,
        bytes calldata hookData
    ) internal virtual override(AaveFeesHook, AllowlistedHook, BaseHook) returns (bytes4, BeforeSwapDelta, uint24) {
        return super._beforeSwap(sender, _key, swapParams, hookData);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal virtual override(AaveFeesHook, BaseHook) returns (bytes4 selector, int128 hookDelta) {
        return AaveFeesHook._afterSwap(sender, _key, swapParams, delta, hookData);
    }

    function _afterHookDeposit(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override(AaveFeesHook, CustodyHook)
    {
        return AaveFeesHook._afterHookDeposit(amount0, amount1, receiver);
    }

    // todo: check it calls all three overrides
    function _beforeHookDeposit(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override(AaveFeesHook, DepositCapHook, AllowlistedHook)
    {
        return super._beforeHookDeposit(amount0, amount1, receiver);
    }

    function _beforeHookWithdrawal(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override(AaveFeesHook, CustodyHook)
    {
        return AaveFeesHook._beforeHookWithdrawal(amount0, amount1, receiver);
    }

    function _afterHookWithdrawal(uint256 amount0, uint256 amount1, address receiver)
        internal
        virtual
        override(AaveFeesHook, CustodyHook)
    {
        return AaveFeesHook._afterHookWithdrawal(amount0, amount1, receiver);
    }

    function _beforeInitialize(address sender, PoolKey calldata poolKey, uint160 sqrtPriceX96)
        internal
        virtual
        override(AaveFeesHook, ExtendedHook)
        returns (bytes4)
    {
        return AaveFeesHook._beforeInitialize(sender, poolKey, sqrtPriceX96);
    }
}
