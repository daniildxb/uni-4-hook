// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {HookV1} from "../src/HookV1.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";


/// @notice Provides liquidity to an existing pool
contract DeployScript is Script, Deployers {
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;

    bytes poolId = "0xeb6ae251698fb547ede500caff0ce8a9e336e014f2725d52bd12961cd12c97af";

    HookV1 hook = HookV1(0x6892e11f6DEC911AA08982bC67748329707848C0);
    address receiver = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);

    function run() public {
        // usdc
        uint256 maxTokenAmount0 = 100 * 1e6;
        uint256 maxTokenAmount1 = 100 * 1e6;

        uint128 liquidity = hook.getLiquidityForTokenAmount0(maxTokenAmount0, maxTokenAmount1);
        BalanceDelta delta = hook.getPoolDelta(uint256(liquidity).toInt128());
        uint256 tokenAmount0 = uint256(int256(delta.amount0()));
        uint256 tokenAmount1 = uint256(int256(delta.amount1()));
        // Provide liquidity to the pool
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        IERC20(Currency.unwrap(hook.token0())).approve(address(hook), tokenAmount0);
        IERC20(Currency.unwrap(hook.token1())).approve(address(hook), tokenAmount1);
        hook.deposit(
            uint256(liquidity),
            receiver
        );
        vm.stopBroadcast();
    }
}
