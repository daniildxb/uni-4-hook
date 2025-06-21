// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CustodyHook} from "./CustodyHook.sol";
import {RolesHook} from "./RolesHook.sol";

/**
 * @title Hook that introduces a deposit cap
 * Using AllowlistedHook as a base to utilize admin functionality
 * todo: add rbac hook as a base here
 */
abstract contract DepositCapHook is CustodyHook, RolesHook {
    uint256 public depositCap0;
    uint256 public depositCap1;

    function setDepositCaps(uint256 _cap0, uint256 _cap1) external onlyHookManager {
        depositCap0 = _cap0;
        depositCap1 = _cap1;
    }

    // Overriding hook instead of deposit function since it already has amounts
    function _beforeHookDeposit(uint256 amount0, uint256 amount1, address receiver) internal virtual override {
        // if any of the caps are 0 - we assume that the cap is disabled
        if (depositCap0 == 0 || depositCap1 == 0) {
            return super._beforeHookDeposit(amount0, amount1, receiver);
        }
        // converting assets to liquidity instead of just taking balanceOf() for HotBuffer
        // negative values are returned
        (int128 _token0HookBalance, int128 _token1HookBalance) = getTokenAmountsForLiquidity(totalAssets());

        if (uint256(int256(-_token0HookBalance)) + amount0 > depositCap0) {
            revert("Deposit cap reached for token0");
        }
        if (uint256(int256(-_token1HookBalance)) + amount1 > depositCap1) {
            revert("Deposit cap reached for token1");
        }
        return super._beforeHookDeposit(amount0, amount1, receiver);
    }
}
