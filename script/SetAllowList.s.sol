// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Config} from "./base/Config.sol";
import {ModularHookV1} from "src/ModularHookV1.sol";
import {HookManager} from "src/HookManager.sol";

/// @notice Sets allowlist and adds address to it
contract SetAllowListScript is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    HookManager public hookManager;
    bool public desiredAllowListStatus = true; // true to enable, false to disable

    function run() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 pool_enum = vm.envUint("POOL_ENUM"); // 0 USDC/USDT ; 1 USDT/DAI

        Config.ConfigData memory configData = getConfigPerNetwork(chainId, pool_enum);

        // Access the hook manager from the config
        hookManager = HookManager(configData.hookManager);
        ModularHookV1 hook = ModularHookV1(address(configData.poolKey.hooks));

        bool allowListState = hook.isAllowlistEnabled();
        bool isAddressInAllowList = hook.allowlist(receiver);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        if (allowListState != desiredAllowListStatus) {
            // Set the allowlist status
            hookManager.flipAllowlist(address(hook));
            hookManager.flipAddressInAllowList(address(hook), receiver);
            hookManager.flipSwapperAllowlist(address(hook));
            hookManager.flipAddressInSwapperAllowList(address(hook), receiver);
            console.log("Allowlist status set to", desiredAllowListStatus);
        } else {
            console.log("Allowlist already in desired state:", allowListState);
        }
        vm.stopBroadcast();
    }
}
