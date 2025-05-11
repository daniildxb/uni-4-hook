// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AaveFeesHook} from "./hooks/AaveFeesHook.sol";
import {AaveHook} from "./hooks/AaveHook.sol";
import {ExtendedHook} from "./hooks/ExtendedHook.sol";
import {HotBufferHook} from "./hooks/HotBufferHook.sol";
import {FeeTrackingHook} from "./hooks/FeeTrackingHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

struct ModularHookV1HookConfig {
    IPoolManager poolManager;
    Currency token0;
    Currency token1;
    int24 tickMin;
    int24 tickMax;
    address aavePoolAddressesProvider;
    string shareName;
    string shareSymbol;
    address feeCollector;
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
contract ModularHookV1 is AaveFeesHook {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;

    constructor(ModularHookV1HookConfig memory config)
        AaveHook(config.aavePoolAddressesProvider)
        HotBufferHook(config.bufferSize0, config.bufferSize1, config.minTransferAmount0, config.minTransferAmount1)
        ExtendedHook(config.poolManager, config.token0, config.token1, config.tickMin, config.tickMax)
        FeeTrackingHook(config.feeCollector, config.fee_bps)
        ERC4626(IERC20(Currency.unwrap(config.token0)))
        ERC20(config.shareName, config.shareSymbol)
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
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

    function _beforeFeesCollected(uint128 amount0, uint128 amount1, address treasury) internal virtual override {}
    function _afterFeesCollected(uint128 amount0, uint128 amount1, address treasury) internal virtual override {}
}
