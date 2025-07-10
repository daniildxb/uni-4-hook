// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {RolesHook} from "./RolesHook.sol";

/**
 * @title Rescue hook
 * @notice This hook allows owner to rescue any erc20 tokens that are sent to the hook
 */
abstract contract RescueHook is RolesHook {
    event ERC20Rescued(address rescuer, address token, uint256 amount);

    using SafeERC20 for IERC20Metadata;

    // todo: right now this allows hook manager to drain the pool
    // it's kept like this for dev testing purposes and will be removed before launch
    function rescue(address token, uint256 amount, address sendTo) external virtual onlyHookManager {
        uint256 balance = IERC20Metadata(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");
        require(amount > 0, "Zero amount");
        emit ERC20Rescued(sendTo, token, amount);
        IERC20Metadata(token).safeTransfer(sendTo, amount);
    }
}
