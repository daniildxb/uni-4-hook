// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {HookV1} from "../../src/HookV1.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";


/// @notice Shared configuration between scripts
contract Config {
    PoolKey poolKey = PoolKey({
        currency0: Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)), // USDC
        currency1: Currency.wrap(address(0xdAC17F958D2ee523a2206206994597C13D831ec7)), // USDT
        fee: 10,
        tickSpacing: 1,
        hooks: IHooks(0xdA29B9f65CA0E10Fc96A3b665CD45D75d6C548C0)
    });

    bytes poolId = "0x8151abca3914de6ebfda6e05e3ade9000722a9dee5359d66e8ce7ee5e0f8da67";
    HookV1 hook = HookV1(0xdA29B9f65CA0E10Fc96A3b665CD45D75d6C548C0);
    address receiver = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);

    struct ConfigData {
        address poolManager;
        address aavePoolAddressesProvider;
        Currency token0;
        Currency token1;
    }

    function getConfigPerNetwork(uint256 chainId) public returns (ConfigData memory) {
        if (chainId == 1) {
            // Mainnet
            return _getMainnetConfigs();
        } else if (chainId == 11155111) {
            // Sepolia
            return _getSepoliaConfigs();
        } else {
            revert("Unsupported network");
        }
    }


    function _getMainnetConfigs() private returns (ConfigData memory) {
        return ConfigData({
            poolManager: address(0x000000000004444c5dc75cB358380D2e3dE08A90),
            aavePoolAddressesProvider: address(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e),
            token0: Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)), // USDC
            token1: Currency.wrap(address(0xdAC17F958D2ee523a2206206994597C13D831ec7)) // USDT
        });
    }

    function _getSepoliaConfigs() private returns (ConfigData memory) {
        return ConfigData({
            poolManager: address(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543),
            aavePoolAddressesProvider: address(0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A),
            token0: Currency.wrap(address(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8)), // USDC
            token1: Currency.wrap(address(0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0)) // USDT
        });
    }
}
