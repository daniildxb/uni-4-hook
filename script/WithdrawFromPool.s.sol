// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Config} from "./base/Config.sol";
import {HookV1} from "../src/HookV1.sol";

/// @notice Withdraws liquidity from an existing pool
/// todo: handle recent changes to config structur
contract WithdrawFromPoolScript is Script, Deployers, Config {
    using SafeCast for *;
    using SafeERC20 for IERC20;

    function run() public {
        uint256 chainId = vm.envUint("CHAIN_ID");
        Config.ConfigData memory config = getConfigPerNetwork(chainId);
        HookV1 hook = HookV1(address(config.poolKey.hooks));

        uint256 shares = hook.balanceOf(receiver);
        console.log("shares", shares);
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        hook.redeem(shares, receiver, receiver);

        vm.stopBroadcast();
    }
}
