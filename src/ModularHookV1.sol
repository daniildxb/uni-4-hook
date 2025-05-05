// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AaveFeesHook} from "./hooks/AaveFeesHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

/**
 * @title Modular Hook V1
 * @notice Most of the functionality is inherited, only defines permissions
 * and overrides for abstract methods
 */
contract ModularHookV1 is AaveFeesHook {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeERC20 for IERC20;

    constructor(
        IPoolManager _poolManager,
        Currency _token0,
        Currency _token1,
        int24 _tickMin,
        int24 _tickMax,
        address _aavePoolAddressesProvider,
        string memory _shareName,
        string memory _shareSymbol,
        address _feeCollector,
        uint256 _fee_bps
    )
        AaveFeesHook(
            _poolManager,
            _token0,
            _token1,
            _tickMin,
            _tickMax,
            _aavePoolAddressesProvider,
            _shareName,
            _shareSymbol,
            _feeCollector,
            _fee_bps
        )
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
