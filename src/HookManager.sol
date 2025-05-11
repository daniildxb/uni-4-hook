// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHookDeployer} from "./HookDeployer.sol";
import {ModularHookV1HookConfig} from "./ModularHookV1.sol";

//
contract HookManager {
    event HookDeployed(address indexed hook, bytes32 indexed poolId, uint256 hookIndex, uint160 sqrtPriceX96);

    address public admin;
    address public poolManager;
    address public hookDeployer;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;


    mapping(bytes32 => address) public poolIdToHook;
    mapping(address => bytes32) public hookToPoolId;
    mapping(uint256 => address) public indexToHook;
    uint256 public hookCount = 0;

    constructor(address _poolManager) {
        poolManager = _poolManager;
        admin = msg.sender;
    }

    function setHookDeployer(address _hookDeployer) external {
        require(msg.sender == admin, "Only admin can set hook deployer");
        hookDeployer = _hookDeployer;
    }

    function deployHook(
        ModularHookV1HookConfig calldata hookParams,
        address expectedAddress,
        uint24 fee,
        int24 tickSpacing,
        bytes32 salt
    ) external {
        require(msg.sender == admin, "Only admin can deploy hooks");
        (address hook, bytes32 poolId) =
            IHookDeployer(hookDeployer).deployHook(poolManager, hookParams, expectedAddress, fee, tickSpacing, SQRT_PRICE_1_1, salt);

        _storeHook(address(hook), poolId);
        emit HookDeployed(address(hook), poolId, hookCount, SQRT_PRICE_1_1);
        hookCount++;
    }

    function _storeHook(address hook, bytes32 poolId) internal {
        require(poolIdToHook[poolId] == address(0), "Hook already exists for this poolId");
        poolIdToHook[poolId] = hook;
        hookToPoolId[hook] = poolId;
        indexToHook[hookCount] = hook;
    }
}
