// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract MockAavePoolAddressesProvider is Test {
    address public pool;
    
    constructor(address _pool) {
        pool = _pool;
    }

    function getPool() external view returns (address) {
        console.log("getPool");
        return pool;
    }
}