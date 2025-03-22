// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

// import {Hooks} from "v4-core/src/libraries/Hooks.sol";
// import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
// import {PoolKey} from "v4-core/src/types/PoolKey.sol";
// import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
// import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
// import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
// import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// /**
//     * @title Lending Hook
//     * @notice Hook for lending assets in Uniswap V4 pools
//     * In addition to regular hook methods, this hook takes ownership of user LP position and lends it
//     * into AAVE protocol.
//     * Hook ensures that no liquidity can be added or removed directly from the pool, only through the hook
// */
// contract Counter is BaseHook, ERC4626 {
//     using PoolIdLibrary for PoolKey;
//     using StateLibrary for IPoolManager;
//     using CurrencyLibrary for Currency;

//     // NOTE: ---------------------------------------------------------
//     // state variables should typically be unique to a pool
//     // a single hook contract should be able to service multiple pools
//     // ---------------------------------------------------------------

//     constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

//     // takes in initial parameters
//     // pool key, tick min, tick max
//     // aave addresses
//     function initialize() public {

//     }

//     /** @dev overrides totalAssets to include total liquidity in both tokens
//      */
//     function totalAssets() public view virtual returns (uint256) {
//         return _asset.balanceOf(address(this));
//     }

//     function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
//         return Hooks.Permissions({
//             beforeInitialize: false,
//             afterInitialize: false,
//             beforeAddLiquidity: true,
//             afterAddLiquidity: true,
//             beforeRemoveLiquidity: true,
//             afterRemoveLiquidity: true,
//             beforeSwap: true,
//             afterSwap: true,
//             beforeDonate: false,
//             afterDonate: false,
//             beforeSwapReturnDelta: false,
//             afterSwapReturnDelta: false,
//             afterAddLiquidityReturnDelta: false,
//             afterRemoveLiquidityReturnDelta: false
//         });
//     }

//     function addLiquidity(address token, uint256 amount) public {
//         // IERC20(token).transferFrom(msg.sender, address(this), amount);
//     }

//     function removeLiquidity(address token, uint256 amount) public {
//         // IERC20(token).transfer(msg.sender, amount);
//     }

//     // -----------------------------------------------
//     // NOTE: see IHooks.sol for function documentation
//     // -----------------------------------------------

//     // withdraws liquidity from aave and deposits into existing position
//     function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
//         internal
//         override
//         returns (bytes4, BeforeSwapDelta, uint24)
//     {
//         beforeSwapCount[key.toId()]++;
//         return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
//     }

//     // withdraws liquidity from the position and puts it into aave
//     function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
//         internal
//         override
//         returns (bytes4, int128)
//     {
//         afterSwapCount[key.toId()]++;

//         return (BaseHook.afterSwap.selector, 0);
//     }

//     // ensures that liquidity is only added through the hook
//     function _beforeAddLiquidity(
//         address,
//         PoolKey calldata key,
//         IPoolManager.ModifyLiquidityParams calldata,
//         bytes calldata
//     ) internal override returns (bytes4) {
//         require (!liquidityInitialized || sender == address(this), "Add Liquidity through Hook");
//         liquidityInitialized = true;
//         return this.beforeAddLiquidity.selector;
//     }

//     // moves added liquidity to the aave pools
//     function _afterAddLiquidity(
//         address sender,
//         PoolKey calldata key,
//         IPoolManager.ModifyLiquidityParams calldata params,
//         BalanceDelta delta,
//         BalanceDelta feesAccrued,
//         bytes calldata hookData
//     ) internal override returns (bytes4) {

//         AavePool.supply(asset0, amount0, address(this));
//         AavePool.supply(asset1, amount1, address(this));

//         return BaseHook.beforeAddLiquidity.selector;
//     }

//     // ensures that liquidity is only removed through the hook
//     function _beforeRemoveLiquidity(
//         address,
//         PoolKey calldata key,
//         IPoolManager.ModifyLiquidityParams calldata,
//         bytes calldata
//     ) internal override returns (bytes4) {
//         beforeRemoveLiquidityCount[key.toId()]++;
//         return BaseHook.beforeRemoveLiquidity.selector;
//     }

//     // moves remaining funds back to aave (todo is it needed if we only withdraw specific amounts ?)
//     function _afterRemoveLiquidity(
//         address,
//         PoolKey calldata key,
//         IPoolManager.ModifyLiquidityParams calldata,
//         bytes calldata
//     ) internal override returns (bytes4) {
//         beforeRemoveLiquidityCount[key.toId()]++;
//         return BaseHook.beforeRemoveLiquidity.selector;
//     }
// }
