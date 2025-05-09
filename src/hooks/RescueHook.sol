// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title Rescue hook
 * @notice This hook allows owner to rescue any erc20 tokens that are sent to the hook
 */
abstract contract RescueHook {
    event ERC20Rescued(address rescuer, address token, uint256 amount);

    address public constant admin = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);

    using SafeERC20 for IERC20;

    function rescue(address token, uint256 amount) external virtual {
        require(msg.sender == admin, "Not owner");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");
        require(amount > 0, "Zero amount");
        emit ERC20Rescued(msg.sender, token, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
