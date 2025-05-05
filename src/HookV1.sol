// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import "forge-std/Test.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC4626Wrapper} from "./ERC4626Wrapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurrencySettler} from "v4-periphery/lib/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPoolAddressesProvider.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Lending Hook
 * @notice Hook for lending assets in Uniswap V4 pools
 * To be removed in favour of modular contracts
 * In addition to regular hook methods, this hook takes ownership of user LP position and lends it
 * into AAVE protocol.
 * Hook ensures that no liquidity can be added or removed directly from the pool, only through the hook
 */
contract HookV1 is BaseHook, ERC4626Wrapper, Test {
    event Deposit(address indexed sender, address indexed owner, uint256 assets0, uint256 assets1, uint256 shares);
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
    using SafeERC20 for IERC20;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    int24 public tickMin;
    int24 public tickMax;
    IPoolAddressesProvider public aavePoolAddressesProvider;
    Currency public token0;
    Currency public token1;
    address aToken0;
    address aToken1;
    bool public liquidityInitialized;
    PoolKey public key;

    constructor(
        IPoolManager _poolManager,
        Currency _token0,
        Currency _token1,
        int24 _tickMin,
        int24 _tickMax,
        address _aavePoolAddressesProvider,
        string memory _shareName,
        string memory _shareSymbol
    ) BaseHook(_poolManager) ERC4626Wrapper(IERC20(Currency.unwrap(_token0))) ERC20(_shareName, _shareSymbol) {
        token0 = _token0;
        token1 = _token1;
        tickMin = _tickMin;
        tickMax = _tickMax;
        console.log("pool address");
        aavePoolAddressesProvider = IPoolAddressesProvider(_aavePoolAddressesProvider);
        console.log("atoken0");
        aToken0 = IPool(aavePoolAddressesProvider.getPool()).getReserveData(Currency.unwrap(token0)).aTokenAddress;
        console.log("atoken1");
        aToken1 = IPool(aavePoolAddressesProvider.getPool()).getReserveData(Currency.unwrap(token1)).aTokenAddress;
        console.log("constructor done");
    }

    // todo: the contract should support multiple pools and differentiate based on the passed poolKey
    function addPool(PoolKey calldata _key) public {
        assert(_key.currency0 == token0);
        assert(_key.currency1 == token1);
        key = _key;
    }

    //
    //  <---- ERC4626 OVERRIDES ---->
    //

    /**
     * @dev we use liquidity as an underlying asset
     */
    function totalAssets() public view override returns (uint256) {
        // this will return 0, since pool actually has no liquidity by default
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

    //
    //  <---- HOOK METHODS ---->
    //
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

    // encodes liqudiity addition params and unlocks poolManager with them
    function deposit(uint256 liquidity, address receiver) public override returns (uint256) {
        console.log("adding liquidity called");
        // erc4626 deposit
        uint256 maxAssets = maxDeposit(receiver);
        if (liquidity > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, liquidity, maxAssets);
        }
        uint256 shares = previewDeposit(liquidity);

        // getting actual token values
        // they are guaranteed to be negative
        BalanceDelta delta = getPoolDelta(liquidity.toInt128());
        // transfer tokens from sender to this contract
        uint256 amount0 = uint256(int256(-delta.amount0()));
        uint256 amount1 = uint256(int256(-delta.amount1()));

        // supply to aave
        IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), amount1);
        _depositToAave(Currency.unwrap(key.currency0), amount0);
        _depositToAave(Currency.unwrap(key.currency1), amount1);
        // we are issuing shares based on the liquidity

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, amount0, amount1, shares);
        return shares;
    }

    // todo: enforce approval check
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256 assets) {
        // we are burning shares based on the liquidity
        console.log("liquidity removal called");

        // need to verify user has shares
        uint256 maxShares = balanceOf(msg.sender);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(msg.sender, shares, maxShares);
        }

        uint256 totalLiquidity = totalAssets();
        assets = (shares * totalLiquidity) / totalSupply();

        BalanceDelta userDelta = getPoolDelta(-assets.toInt128());

        _withdraw(msg.sender, receiver, owner, assets, shares);

        _withdrawFromAave(Currency.unwrap(token0), uint256(int256(userDelta.amount0())), receiver);
        _withdrawFromAave(Currency.unwrap(token1), uint256(int256(userDelta.amount1())), receiver);
    }

    // some black magic copied from the Pool.sol::modifyLiquidity()
    function getPoolDelta(int128 liquidityDelta) public view returns (BalanceDelta delta) {
        (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(key.toId());
        console.log("current tick", tick);
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

    // VIEWS

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

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    // withdraws liquidity from aave and deposits into existing position
    function _beforeSwap(address sender, PoolKey calldata _key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        console.log("Before swap called");

        // fetch token balances and put them into liquidity
        uint256 liquidityDelta = totalAssets();

        _withdrawFromAave(Currency.unwrap(token0), type(uint256).max, address(this));
        _withdrawFromAave(Currency.unwrap(token1), type(uint256).max, address(this));

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

    // withdraws liquidity from the position and puts it into aave
    function _afterSwap(address, PoolKey calldata _key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        console.log("After swap called");

        // fetch existing liqudity
        // withdraw liquidity from PoolManager
        uint128 liquidity = poolManager.getLiquidity(key.toId());

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickMin,
            tickUpper: tickMax,
            liquidityDelta: int256(-int128(liquidity)),
            salt: 0
        });

        (BalanceDelta delta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(key, params, abi.encode(0));

        console.log(delta.amount0());
        console.log(delta.amount1());

        console.log(IERC20(Currency.unwrap(token0)).balanceOf(address(poolManager)));

        // note:
        // this may not work as pool manager currently has only original LP tokens
        // and swap hasn't taken effect yet
        // to ensure 100% effectivenss we'd need to route all swaps through the hook and
        // withdraw liquidity after swap is settled, this would mess up v4 optimizations
        // but at the moment this seems like the only fully on-chain solution

        // note: instead we are relying on PoolManager having more liquidity from other sources
        // just need to verify token balances on PoolManager and transfer as much as possible
        // the rest will be deposit to AAVE on the next swap / LP change
        poolManager.take(token0, address(this), uint256(int256(delta.amount0())));
        poolManager.take(token1, address(this), uint256(int256(delta.amount1())));

        // deposit to aave
        uint256 amount0 = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(this));
        uint256 amount1 = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));
        _depositToAave(Currency.unwrap(key.currency0), amount0);
        _depositToAave(Currency.unwrap(key.currency1), amount1);

        return (BaseHook.afterSwap.selector, 0);
    }

    // ensures that liquidity is only added through the hook
    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata _key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        require(sender == address(this), "Add Liquidity through Hook");
        liquidityInitialized = true;
        return this.beforeAddLiquidity.selector;
    }

    // Reusable function to deposit tokens into AAVE
    function _depositToAave(address token, uint256 amount) private {
        IERC20(token).forceApprove(aavePoolAddressesProvider.getPool(), amount);
        IPool(aavePoolAddressesProvider.getPool()).supply(token, amount, address(this), 0);
    }

    // Reusable function to withdraw tokens from AAVE
    function _withdrawFromAave(address token, uint256 amount, address receiver) private returns (uint256) {
        return IPool(aavePoolAddressesProvider.getPool()).withdraw(token, amount, receiver);
    }
}
