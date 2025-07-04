// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {CustodyHook} from "./CustodyHook.sol";
import {RolesHook} from "./RolesHook.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

/**
 * @title Hook that only allows deposits from the allowlisted addresses
 */
abstract contract AllowlistedHook is CustodyHook, RolesHook {
    mapping(address => bool) public allowlist;
    mapping(address => bool) public swapperAllowlist;
    bool public isAllowlistEnabled;
    bool public isSwapperAllowlistEnabled;

    function flipAllowlist() external onlyHookManager {
        isAllowlistEnabled = !isAllowlistEnabled;
    }

    function flipAddressInAllowList(address user) external onlyHookManager {
        allowlist[user] = !allowlist[user];
    }

    function flipSwapperAllowlist() external onlyHookManager {
        isSwapperAllowlistEnabled = !isSwapperAllowlistEnabled;
    }

    function flipAddressInSwapperAllowList(address user) external onlyHookManager {
        swapperAllowlist[user] = !swapperAllowlist[user];
    }

    function _beforeHookDeposit(uint256 amount0, uint256 amount1, address receiver) internal virtual override {
        if (!isAllowlistEnabled) {
            return super._beforeHookDeposit(amount0, amount1, receiver);
        }
        bool isAllowed = allowlist[receiver];
        require(isAllowed, "Not allowed");
        return super._beforeHookDeposit(amount0, amount1, receiver);
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata poolkey,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!isSwapperAllowlistEnabled) {
            return super._beforeSwap(sender, poolkey, params, data);
        }
        // using tx.origin as sender is a contract address
        bool isSwapperAllowed = swapperAllowlist[tx.origin];
        require(isSwapperAllowed, "Not allowed");
        return super._beforeSwap(sender, poolkey, params, data);
    }
}
