// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {CustodyHook} from "./CustodyHook.sol";

/**
 * @title Hook that only allows deposits from the allowlisted addresses
 */
abstract contract AllowlistedHook is CustodyHook {
    mapping(address => bool) public allowlist;
    bool public isAllowlistEnabled;

    function flipAllowlist() external {
        require(msg.sender == admin, "Not admin");
        isAllowlistEnabled = !isAllowlistEnabled;
    }

    function flipAddressInAllowList(address user) external {
        require(msg.sender == admin, "Not admin");
        allowlist[user] = !allowlist[user];
    }

    function _beforeHookDeposit(uint256 amount0, uint256 amount1, address receiver) internal virtual override {
        if (!isAllowlistEnabled) {
            return super._beforeHookDeposit(amount0, amount1, receiver);
        }
        bool isAllowed = allowlist[receiver];
        require(isAllowed, "Not allowed");
        return super._beforeHookDeposit(amount0, amount1, receiver);
    }
}
