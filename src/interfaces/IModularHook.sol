// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

// the interface is far from complete, added it for the sake of using with sol! in rust
interface IModularHook {
    function getHookTokens() external view returns (address, address);
}
