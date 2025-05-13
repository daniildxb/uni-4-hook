// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {SqrtPriceCalculator} from "./PriceCalculator.sol";

/// @notice Shared configuration between scripts
contract Config is SqrtPriceCalculator {
    // for tokens with the same decimals
    address receiver = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);
    uint256 fee_bps = 1000; // 10%
    uint256 bufferSize = 1e7; // 10 tokens with 6 decimals
    uint256 minTransferAmount = 1e6; // 1 token with 6 decimals

    // Fee and tick constants
    uint24 constant DEFAULT_FEE = 10;
    int24 constant DEFAULT_TICK_SPACING = 1;

    // Pool identifiers
    uint256 constant USDC_USDT_POOL = 0; // main pool
    uint256 constant USDT_DAI_POOL = 1; // 6/18 decimals
    uint256 constant DAI_USDE_POOL = 2; // won't work
    uint256 constant DAI_GHO_POOL = 3; // 18/18 decimals

    // Network identifiers
    uint256 constant MAINNET = 1;
    uint256 constant ARBITRUM = 42161;
    uint256 constant LOCAL = 0;

    // Token addresses - Mainnet
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Token addresses - Arbitrum
    address constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant ARBITRUM_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant ARBITRUM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant ARBITRUM_USDE = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;
    address constant ARBITRUM_GHO = 0x7dfF72693f6A4149b17e7C6314655f6A9F7c8B33;

    // Infrastructure addresses - Mainnet
    address constant MAINNET_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address constant MAINNET_AAVE_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant MAINNET_HOOK_MANAGER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    // Infrastructure addresses - Arbitrum
    address constant ARBITRUM_POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;
    address constant ARBITRUM_AAVE_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address constant ARBITRUM_HOOK_MANAGER = 0x10BF3E582fc11D5629743E93beDC39b838C603cc;

    address constant LOCAL_HOOK_MANAGER = 0xC06f14998f2B65E7D3dD14F049F827F0DF7Bb8a9;

    struct ConfigData {
        address poolManager;
        address aavePoolAddressesProvider;
        address hookManager;
        Currency token0;
        Currency token1;
        PoolKey poolKey;
        bytes poolId;
    }

    struct TokenPair {
        address token0Address;
        address token1Address;
        address hookAddress;
        bytes poolId;
    }

    // Get available pool IDs for a specific network
    function getAvailablePoolIds(uint256 chainId) public pure returns (uint256[] memory) {
        if (chainId == MAINNET) {
            uint256[] memory poolIds = new uint256[](1);
            poolIds[0] = USDC_USDT_POOL;
            return poolIds;
        } else if (chainId == ARBITRUM) {
            uint256[] memory poolIds = new uint256[](2);
            poolIds[0] = USDC_USDT_POOL;
            poolIds[1] = USDT_DAI_POOL;
            return poolIds;
        } else if (chainId == LOCAL) {
            uint256[] memory poolIds = new uint256[](1);
            poolIds[0] = USDC_USDT_POOL;
            return poolIds;
        } else {
            revert("Unsupported network");
        }
    }

    function getConfigPerNetwork(uint256 chainId, uint256 poolId) public pure returns (ConfigData memory) {
        // Get network base config
        address poolManager;
        address aaveProvider;
        address hookManager;

        if (chainId == MAINNET) {
            poolManager = MAINNET_POOL_MANAGER;
            aaveProvider = MAINNET_AAVE_PROVIDER;
            hookManager = MAINNET_HOOK_MANAGER;
            return _getMainnetPoolConfig(poolId, poolManager, aaveProvider, hookManager);
        } else if (chainId == ARBITRUM) {
            poolManager = ARBITRUM_POOL_MANAGER;
            aaveProvider = ARBITRUM_AAVE_PROVIDER;
            hookManager = ARBITRUM_HOOK_MANAGER;
            return _getArbitrumPoolConfig(poolId, poolManager, aaveProvider, hookManager);
        } else if (chainId == LOCAL) {
            poolManager = MAINNET_POOL_MANAGER;
            aaveProvider = MAINNET_AAVE_PROVIDER;
            hookManager = LOCAL_HOOK_MANAGER;
            return _getLocalPoolConfig(poolId, poolManager, aaveProvider, hookManager);
        } else {
            revert("Unsupported network");
        }
    }

    function _getMainnetPoolConfig(uint256 poolId, address poolManager, address aaveProvider, address hookManager)
        private
        pure
        returns (ConfigData memory)
    {
        TokenPair memory tokenPair;

        if (poolId == USDC_USDT_POOL) {
            tokenPair = TokenPair({
                token0Address: MAINNET_USDC,
                token1Address: MAINNET_USDT,
                hookAddress: 0xdA29B9f65CA0E10Fc96A3b665CD45D75d6C548C0,
                poolId: "0x8151abca3914de6ebfda6e05e3ade9000722a9dee5359d66e8ce7ee5e0f8da67"
            });
        } else {
            revert("Unsupported pool ID for Mainnet");
        }

        return _buildConfigData(poolManager, aaveProvider, hookManager, tokenPair);
    }

    function _getLocalPoolConfig(uint256 poolId, address poolManager, address aaveProvider, address hookManager)
        private
        pure
        returns (ConfigData memory)
    {
        TokenPair memory tokenPair;

        if (poolId == USDC_USDT_POOL) {
            tokenPair = TokenPair({
                token0Address: MAINNET_USDC, // Using mainnet addresses for local development
                token1Address: MAINNET_USDT,
                hookAddress: 0xd9C461354be60457759349378dEF760CeF3Ac8C0,
                poolId: "0x437f292d4e7dbacf4b01f0962ae688e3c6f6838b8ef6e5371c5326e4936618d5"
            });
        } else {
            revert("Unsupported pool ID for Local");
        }

        return _buildConfigData(poolManager, aaveProvider, hookManager, tokenPair);
    }

    function _getArbitrumPoolConfig(uint256 poolId, address poolManager, address aaveProvider, address hookManager)
        private
        pure
        returns (ConfigData memory)
    {
        TokenPair memory tokenPair;

        if (poolId == USDC_USDT_POOL) {
            tokenPair = TokenPair({
                token0Address: ARBITRUM_USDC,
                token1Address: ARBITRUM_USDT,
                hookAddress: 0xEe0e83e362f2F4A969D1d9c6eb04d400Bb1bC8c0,
                poolId: "0x775253e1a54c55f1f0cbc143fb035cd60c459a1db2251b6bc494886f978a0f2a"
            });
        } else if (poolId == USDT_DAI_POOL) {
            tokenPair = TokenPair({
                token0Address: ARBITRUM_DAI,
                token1Address: ARBITRUM_USDT,
                hookAddress: 0xccC7C10b872A9F449FA41Ef7a723ACB1615548C0,
                poolId: "0x7ec8ddf47afeb8e2e6621e879272e1f92e8dd95f0979c22d399b7a3fe280d307"
            });
        } else if (poolId == DAI_GHO_POOL) {
            tokenPair = TokenPair({
                token0Address: ARBITRUM_GHO,
                token1Address: ARBITRUM_DAI,
                hookAddress: 0x7e1993d03BD50AE43dEA6E3d2e1027aB1213C8c0,
                poolId: "0xe4f5712fa24b6300c1c6bb7d821127f701e62ed93adb38024d309fe7a26d1b35"
            });
        } else {
            revert("Unsupported pool ID for Arbitrum");
        }

        return _buildConfigData(poolManager, aaveProvider, hookManager, tokenPair);
    }

    // Helper function to build full config data from base config and token pair
    function _buildConfigData(
        address poolManager,
        address aaveProvider,
        address hookManager,
        TokenPair memory tokenPair
    ) private pure returns (ConfigData memory) {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(tokenPair.token0Address),
            currency1: Currency.wrap(tokenPair.token1Address),
            fee: DEFAULT_FEE,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(tokenPair.hookAddress)
        });

        return ConfigData({
            poolManager: poolManager,
            aavePoolAddressesProvider: aaveProvider,
            hookManager: hookManager,
            token0: Currency.wrap(tokenPair.token0Address),
            token1: Currency.wrap(tokenPair.token1Address),
            poolKey: poolKey,
            poolId: tokenPair.poolId
        });
    }
}
