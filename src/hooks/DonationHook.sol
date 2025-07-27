// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Hook that accepts erc20 donations and emits event
abstract contract DonationHook {
    using SafeERC20 for IERC20Metadata;

    event Donate(address indexed sender, address indexed token, uint256 amount);

    function acceptDonation(address token, uint256 amount) external {
        IERC20Metadata(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Donate(msg.sender, address(token), amount);
    }
}
