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

/// @notice Withdraws liquidity from an existing pool
/// todo: handle recent changes to config structur
contract RescueFromHookScript is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    function run() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        Config.ConfigData memory config = getConfigPerNetwork(chainId);
        ModularHookV1 hook = ModularHookV1(address(config.poolKey.hooks));
        address tokenToRescue = Currency.unwrap(config.token0);
        uint256 amountToRescue = IERC20(tokenToRescue).balanceOf(address(hook));

        if (amountToRescue == 0) {
            console.log("No tokens to rescue");
            return;
        }

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        hook.rescue(tokenToRescue, amountToRescue);
        vm.stopBroadcast();
    }
}
