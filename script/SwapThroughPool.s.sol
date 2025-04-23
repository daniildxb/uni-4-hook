// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {HookV1} from "../src/HookV1.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";


/// @notice Provides liquidity to an existing pool
contract WithdrawScript is Script, Deployers {
    HookV1 hook = HookV1(0x2cA0585b25371Ca433bC56254338392c6ca508C0);
    address receiver = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);

    function run() public {
        uint256 shares = hook.balanceOf(receiver);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        hook.redeem(shares, receiver, receiver);
        vm.stopBroadcast();
    }

}