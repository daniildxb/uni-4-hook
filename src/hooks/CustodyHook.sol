// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ExtendedHook} from "./ExtendedHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {ERC4626Wrapper} from "../ERC4626Wrapper.sol";

/**
 * @title Custody Hook
 * @notice Hook that enforces liquidity provision only through the hook
 * Manages custody of LP positions for users
 */
abstract contract CustodyHook is ExtendedHook, ERC4626Wrapper {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    constructor(
        IPoolManager _poolManager,
        Currency _token0,
        Currency _token1,
        int24 _tickMin,
        int24 _tickMax,
        string memory _shareName,
        string memory _shareSymbol
    )
        ExtendedHook(_poolManager, _token0, _token1, _tickMin, _tickMax)
        ERC4626Wrapper(IERC20(Currency.unwrap(_token0)))
        ERC20(_shareName, _shareSymbol)
    {}

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

    /**
     * @dev Hook users deposit liquidity through this function
     * @param liquidity The amount of liquidity to deposit
     * @param receiver The address to receive LP tokens
     */
    function deposit(uint256 liquidity, address receiver) public virtual override returns (uint256) {
        // ERC4626 deposit check
        uint256 maxAssets = maxDeposit(receiver);
        if (liquidity > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, liquidity, maxAssets);
        }
        uint256 shares = previewDeposit(liquidity);

        // Getting actual token values
        BalanceDelta delta = getPoolDelta(liquidity.toInt128());

        // Transfer tokens from sender to this contract
        uint256 amount0 = uint256(int256(-delta.amount0()));
        uint256 amount1 = uint256(int256(-delta.amount1()));

        _beforeHookDeposit(amount0, amount1);

        // Receive tokens from user
        IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(msg.sender, address(this), amount1);

        // Process the tokens (to be implemented by child contracts)

        // Issue shares to represent the liquidity position
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, amount0, amount1, shares);

        _afterHookDeposit(amount0, amount1);

        return shares;
    }

    /**
     * @dev Allows users to redeem their position
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive tokens
     * @param owner The owner of the shares
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        // Verify user has shares
        uint256 maxShares = balanceOf(msg.sender);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(msg.sender, shares, maxShares);
        }

        // Calculate the amount of liquidity represented by these shares
        uint256 totalLiquidity = totalAssets();
        assets = (shares * totalLiquidity) / totalSupply();

        // Calculate token amounts based on pool state
        BalanceDelta userDelta = getPoolDelta(-assets.toInt128());

        _beforeHookWithdrawal(uint256(int256(userDelta.amount0())), uint256(int256(userDelta.amount1())), receiver);

        // Handle ERC4626 accounting
        _withdraw(msg.sender, receiver, owner, assets, shares);

        // Process the withdrawal (to be implemented by child contracts)
        _afterHookWithdrawal(uint256(int256(userDelta.amount0())), uint256(int256(userDelta.amount1())), receiver);

        return assets;
    }

    /**
     * @dev Hook for processing deposits, to be implemented by child contracts
     */
    function _beforeHookDeposit(uint256 amount0, uint256 amount1) internal virtual;

    /**
     * @dev Hook for processing deposits, to be implemented by child contracts
     */
    function _afterHookDeposit(uint256 amount0, uint256 amount1) internal virtual;

    /**
     * @dev Hook for processing withdrawals, to be implemented by child contracts
     */
    function _beforeHookWithdrawal(uint256 amount0, uint256 amount1, address receiver) internal virtual;

    /**
     * @dev Hook for processing withdrawals, to be implemented by child contracts
     */
    function _afterHookWithdrawal(uint256 amount0, uint256 amount1, address receiver) internal virtual;
}
