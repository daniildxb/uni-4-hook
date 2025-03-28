// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAToken is ERC20 {
    address internal _underlyingAsset;

    constructor(address underlyingAsset, string memory name, string memory symbol) ERC20(name, symbol) {
        _underlyingAsset = underlyingAsset;
    }

    function mint(address caller, address reciever, uint256 amount) external {
        _mint(reciever, amount);
    }

    function burn(address from, address receiver, uint256 amount) external {
        _burn(from, amount);
        ERC20(_underlyingAsset).transfer(receiver, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
