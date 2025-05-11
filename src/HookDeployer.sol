// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ModularHookV1, ModularHookV1HookConfig} from "./ModularHookV1.sol";

interface IHookDeployer {
    function deployHook(
        address poolManager,
        ModularHookV1HookConfig calldata hookParams,
        address expectedAddress,
        bytes32 salt
    ) external returns (address);
}

contract HookDeployer is IHookDeployer {
    address public hookManagerAddress;

    constructor(address _hookManagerAddress) {
        hookManagerAddress = _hookManagerAddress;
    }

    function deployHook(
        address poolManager,
        ModularHookV1HookConfig calldata hookParams,
        address expectedAddress,
        bytes32 salt
    ) external returns (address) {
        require(msg.sender == hookManagerAddress, "Only hook manager can deploy hooks");
        ModularHookV1 hook = new ModularHookV1{salt: salt}(hookParams);
        require(address(hook) == expectedAddress, "HookV1: hook address mismatch");
        return address(hook);
    }
}
