// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import "forge-std/Test.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Slot0, Slot0Library} from "v4-core/src/types/Slot0.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurrencySettler} from "v4-periphery/lib/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPoolAddressesProvider.sol";


/**
 * @title Lending Hook
 * @notice Hook for lending assets in Uniswap V4 pools
 * In addition to regular hook methods, this hook takes ownership of user LP position and lends it
 * into AAVE protocol.
 * Hook ensures that no liquidity can be added or removed directly from the pool, only through the hook
 */
contract HookV1 is BaseHook, ERC4626, Test {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using StateLibrary for IPoolManager;
    using SafeCast for *;

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
    ) BaseHook(_poolManager) ERC4626(IERC20(Currency.unwrap(_token0))) ERC20(_shareName, _shareSymbol) {
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

    // override erc4626 deposit so that we don't transfer actual tokens
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _burn(owner, shares);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    struct CallbackData {
        uint8 action;
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
    }

    bytes constant ZERO_BYTES = new bytes(0);

    // encodes liqudiity addition params and unlocks poolManager with them
    function addLiquidity(IPoolManager.ModifyLiquidityParams calldata params) public {
        // we are issuing shares based on the liquidity
        deposit(uint256(params.liquidityDelta), msg.sender);

        poolManager.unlock(abi.encode(CallbackData(1, msg.sender, key, params, ZERO_BYTES, false, false)));
        // everything below is executed **AFTER** unlockCallback is called
    }

    function removeLiquidity(IPoolManager.ModifyLiquidityParams calldata params) public {
        // we are burning shares based on the liquidity
        console.log("liquidity removal called");

        // need to verify user has shares
        uint256 shares = balanceOf(msg.sender);
        uint256 totalLiquidity = totalAssets();
        uint256 sharesWorth = (shares * totalLiquidity) / totalSupply();

        BalanceDelta userDelta = getPoolDelta(-sharesWorth.toInt128());

        redeem(uint256(params.liquidityDelta), msg.sender, msg.sender);

        IPool(aavePoolAddressesProvider.getPool()).withdraw(Currency.unwrap(token0), uint256(int256(userDelta.amount0())), msg.sender);
        IPool(aavePoolAddressesProvider.getPool()).withdraw(Currency.unwrap(token1), uint256(int256(userDelta.amount1())), msg.sender);
        // no need to call pool manager
    }

    // handles actions based on the encoded data from the poolManager
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        // move liquidity addition logic to the _beforeSwap - √
        // leave funds at rest here so that they aren't actually added to the pool
        // issue shares based on the amount of funds added
        // provide liqudity in the beforeSwap hook
        // remove liquidity in the afterSwap hook
        if (data.action == 1) {
            // create liquidity addition call

            // get delta
            console.log("adding liquidity called");
            BalanceDelta delta = getPoolDelta(data.params.liquidityDelta.toInt128());
            // transfer tokens from sender to this contract
            uint256 amount0 = uint256(int256(-delta.amount0()));
            uint256 amount1 = uint256(int256(-delta.amount1()));
            IERC20(Currency.unwrap(key.currency0)).transferFrom(
                data.sender, address(this), amount0
            );
            IERC20(Currency.unwrap(key.currency1)).transferFrom(
                data.sender, address(this), amount1
            );
            IERC20(Currency.unwrap(key.currency0)).approve(aavePoolAddressesProvider.getPool(), amount0);
            IERC20(Currency.unwrap(key.currency1)).approve(aavePoolAddressesProvider.getPool(), amount1);
            IPool(aavePoolAddressesProvider.getPool()).supply(Currency.unwrap(key.currency0), amount0, address(this), 0);
            IPool(aavePoolAddressesProvider.getPool()).supply(Currency.unwrap(key.currency1), amount1, address(this), 0);
        } else {
            console.log("action", data.action);
            revert("not supported yet");
        }
    }

    // some black magic copied from the Pool.sol::modifyLiquidity()
    function getPoolDelta(int128 liquidityDelta) internal view returns (BalanceDelta delta) {
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

        uint256 token0Balance = IPool(aavePoolAddressesProvider.getPool()).withdraw(Currency.unwrap(token0), type(uint256).max, address(this));
        uint256 token1Balance = IPool(aavePoolAddressesProvider.getPool()).withdraw(Currency.unwrap(token1), type(uint256).max, address(this));

        // need to convert existing balances to liquidity amount
        // for this we need to get current pool price and calculate amount of liquidity between
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickMin),
            TickMath.getSqrtPriceAtTick(tickMax),
            token0Balance,
            token1Balance
        );

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickMin,
            tickUpper: tickMax,
            liquidityDelta: int256(int128(liquidityDelta)),
            salt: 0
        });

        (BalanceDelta delta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(key, params, abi.encode(0));

        // transfer tokens to the poolManager
        // todo: maybe we don't need to actually call settle...
        CurrencySettler.settle(key.currency0, poolManager, address(this), uint256(int256(-delta.amount0())), false);
        CurrencySettler.settle(key.currency1, poolManager, address(this), uint256(int256(-delta.amount1())), false);
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
        IERC20(Currency.unwrap(key.currency0)).approve(aavePoolAddressesProvider.getPool(), amount0);
        IERC20(Currency.unwrap(key.currency1)).approve(aavePoolAddressesProvider.getPool(), amount1);
        IPool(aavePoolAddressesProvider.getPool()).supply(Currency.unwrap(key.currency0), amount0, address(this), 0);
        IPool(aavePoolAddressesProvider.getPool()).supply(Currency.unwrap(key.currency1), amount1, address(this), 0);
            
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

    // moves added liquidity to the aave pools
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata _key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // ensures that liquidity is only removed through the hook
    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata _key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    // moves remaining funds back to aave (todo is it needed if we only withdraw specific amounts ?)
    function _afterRemoveLiquidity(
        address,
        PoolKey calldata _key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        return (BaseHook.beforeRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }
}
