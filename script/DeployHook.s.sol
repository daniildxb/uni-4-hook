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

/// @notice Mines the address and deploys the HookV1.sol Hook contract
contract DeployScript is Script, Deployers {
    using PoolIdLibrary for PoolKey;

    IPoolManager constant POOLMANAGER = IPoolManager(address(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543));
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function run() external {
        //  hook contracts must have specific flags encoded in the address
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144);

        // @note we need to pass those in an order
        // usdt
        Currency token1 = Currency.wrap(address(0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0));
        // usdc
        Currency token0 = Currency.wrap(address(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8));
        int24 _tickMin = 0;
        int24 _tickMax = 3000;
        address aavePoolAddressesProvider = address(0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A);
        string memory shareName = "LP";
        string memory shareSymbol = "LP";

        manager = POOLMANAGER;

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            POOLMANAGER, token0, token1, _tickMin, _tickMax, aavePoolAddressesProvider, shareName, shareSymbol
        );

        // Move the mining and deployment into the run function where execution occurs
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(HookV1).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        HookV1 hook = new HookV1{salt: salt}(
            POOLMANAGER, token0, token1, _tickMin, _tickMax, aavePoolAddressesProvider, shareName, shareSymbol
        );
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "HookV1: hook address mismatch");

        // create pool
        uint24 fee = 3000;
        // PoolKey memory key = PoolKey({
        //     currency0: token0,
        //     currency1: token1,
        //     fee: fee,
        //     tickSpacing: int24(fee / 100 * 2),
        //     hooks: IHooks(hook)
        // });
        // it fails for some reason :(
        // need to debug using tests
        (key,) = initPool(token0, token1, IHooks(address(hook)), fee, SQRT_PRICE_1_1);

        // add pool
        hook.addPool(key);
    }
    
}
