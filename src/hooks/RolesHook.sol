// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title Rescue hook
 * @notice This hook allows owner to rescue any erc20 tokens that are sent to the hook
 */
abstract contract RolesHook {
    address public immutable hookManager;

    constructor(address _hookManager) {
        hookManager = _hookManager;
    }

    modifier onlyHookManager() {
        require(msg.sender == hookManager, "Not hook manager");
        _;
    }
}
