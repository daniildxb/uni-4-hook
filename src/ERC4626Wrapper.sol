// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @title ERC4626Wrapper
 * @dev This contract is a wrapper for the ERC4626 contract.
 * It overrides pretty much all entry points to it, to be able to use share calculations
 */
abstract contract ERC4626Wrapper is ERC4626 {
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {}

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {}

    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {}

    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {}

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
}
