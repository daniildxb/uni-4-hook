// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../../BaseTest.sol";
import {HookManager} from "src/HookManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {ModularHookV1, ModularHookV1HookConfig} from "src/ModularHookV1.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title HookManagerTest
 * @notice Tests for the HookManager contract focusing on the getAllHooks method
 */
contract HookManagerTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    
    address public secondHookAddress;
    PoolKey public secondPoolKey;
    PoolId public secondPoolId;
    
    function setUp() public override {
        super.setUp();
        // The base setup already deploys a hook and registers it with the hook manager
    }
    
    function test_getAllHooks() public view {
        // Get all hooks registered with the hook manager
        address[] memory hooks = hookManager.getAllHooks();
        
        // Verify array length - we should have 1 hook deployed (from BaseTest setup)
        require(hooks.length == 1, "Hook array length should be 1");
        
        // Verify the hook in the array matches our deployed hook
        require(hooks[0] == address(hook), "Hook address mismatch");
    }
    
    function test_hookManagement() public view {
        // Test the hook count is correct
        require(hookManager.hookCount() == 1, "Hook count should be 1");
        
        // Test indexToHook mapping
        require(hookManager.indexToHook(0) == address(hook), "Hook index mapping is incorrect");
        
        // Test poolIdToHook mapping
        require(hookManager.poolIdToHook(simplePoolId) == address(hook), "Pool ID to hook mapping is incorrect");
        
        // Test hookToPoolId mapping
        require(PoolId.unwrap(hookManager.hookToPoolId(address(hook))) == PoolId.unwrap(simplePoolId), 
            "Hook to pool ID mapping is incorrect");
    }
    
    function test_multipleHooksTracking() public {
        // Get initial hooks count
        uint256 initialHookCount = hookManager.hookCount();
        require(initialHookCount == 1, "Initial hook count should be 1");
        
        // Deploy a second hook
        vm.startPrank(admin);
        _deploySecondHook();
        vm.stopPrank();
        
        // Get updated hooks count
        uint256 updatedHookCount = hookManager.hookCount();
        require(updatedHookCount == 2, "Hook count after deployment should be 2");
        
        // Get all hooks
        address[] memory hooks = hookManager.getAllHooks();
        
        // Verify array length
        require(hooks.length == 2, "Hook array length should be 2");
        
        // Verify both hooks are in the array
        require(hooks[0] == address(hook), "First hook address mismatch");
        require(hooks[1] == secondHookAddress, "Second hook address mismatch");
        
        // Verify mappings for the second hook
        require(hookManager.indexToHook(1) == secondHookAddress, "Second hook index mapping is incorrect");
        require(hookManager.poolIdToHook(secondPoolId) == secondHookAddress, "Second hook pool ID mapping is incorrect");
        require(PoolId.unwrap(hookManager.hookToPoolId(secondHookAddress)) == PoolId.unwrap(secondPoolId), 
            "Hook to pool ID mapping for second hook is incorrect");
    }
    
    function _deploySecondHook() internal {
        // We need a different hook with a unique pool key
        // First, we need to deploy a second hook with a different pool key
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x5555 << 144); // Different namespace
        
        ModularHookV1HookConfig memory hookParams = ModularHookV1HookConfig({
            poolManager: IPoolManager(manager),
            token0: token0, 
            token1: token1,
            tickMin: tickMin - 10, // Different tick range to make a different pool
            tickMax: tickMax + 10,
            aavePoolAddressesProvider: aavePoolAddressesProvider,
            shareName: "Second Hook",
            shareSymbol: "SH",
            fee_bps: fee_bps,
            bufferSize0: bufferSize,
            bufferSize1: bufferSize,
            minTransferAmount0: minTransferAmount,
            minTransferAmount1: minTransferAmount
        });
        
        bytes memory constructorArgs = abi.encode(hookParams);
        bytes memory creationCode = abi.encodePacked(type(ModularHookV1).creationCode, constructorArgs);
        
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(hookManager), flags, type(ModularHookV1).creationCode, constructorArgs);
            
        // Use a different fee tier to get a different pool key with the same tokens
        uint24 secondFee = 500; // Different fee from the first hook
        
        // Deploy the second hook through the HookManager
        hookManager.deployHook(
            hookParams.token0, 
            hookParams.token1, 
            hookAddress, 
            SQRT_PRICE_1_1, 
            secondFee, // Different fee for different pool key 
            tickSpacing, 
            salt, 
            creationCode
        );
        
        secondHookAddress = hookAddress;
        secondPoolKey = PoolKey({
            currency0: token0, 
            currency1: token1, 
            fee: secondFee, 
            tickSpacing: tickSpacing, 
            hooks: IHooks(secondHookAddress)
        });
        secondPoolId = secondPoolKey.toId();
    }
}