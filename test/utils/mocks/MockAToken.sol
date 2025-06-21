// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAToken is ERC20 {
    address internal _underlyingAsset;
    uint8 internal _decimals;

    constructor(address underlyingAsset, string memory name, string memory symbol, uint8 dec) ERC20(name, symbol) {
        _underlyingAsset = underlyingAsset;
        _decimals = dec;
    }

    function mint(address caller, address reciever, uint256 amount) external {
        _mint(reciever, amount);
    }

    function burn(address from, address receiver, uint256 amount) external {
        _burn(from, amount);
        ERC20(_underlyingAsset).transfer(receiver, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
