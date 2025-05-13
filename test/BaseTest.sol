// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {MockAToken} from "./utils/mocks/MockAToken.sol";
import {MockAavePool} from "./utils/mocks/MockAavePool.sol";
import {MockAavePoolAddressesProvider} from "./utils/mocks/MockAavePoolAddressesProvider.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {HookManager} from "src/HookManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Create2Impl} from "permit2/lib/openzeppelin-contracts/contracts/mocks/Create2Impl.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {ModularHookV1, ModularHookV1HookConfig} from "../src/ModularHookV1.sol";

contract BaseTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;

    Currency token0;
    Currency token1;
    // todo: update to use 60 / -60 ticks an 0.01% fee
    int24 tickMin = -3000;
    int24 tickMax = 3000;
    address aavePoolAddressesProvider;
    string shareName = "name";
    string shareSymbol = "symbol";
    HookManager hookManager;
    ModularHookV1 hook; // Changed from HookV1 to ModularHookV1
    uint24 fee = 3000;
    int24 tickSpacing = 60;
    uint256 fee_bps = 1000; // 10%
    uint256 bufferSize = 1e7;
    uint256 minTransferAmount = 1e6;
    address admin = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    // Test accounts
    address public user1 = address(777);
    address public user2 = address(888);
    uint256 initialTokenBalance = 10000;

    // Common variables for testing
    address token0Address;
    address token1Address;
    address aToken0Address;
    address aToken1Address;

    // Test state
    struct TokenBalances {
        uint256 userToken0;
        uint256 userToken1;
        uint256 hookToken0;
        uint256 hookToken1;
        uint256 hookAToken0;
        uint256 hookAToken1;
    }

    function setUp() public virtual {
        console.log("1");
        deployFreshManagerAndRouters();
        (token0, token1) = deployMintAndApprove2Currencies();
        _deployCreate2();

        console.log("2");
        MockAToken aToken0 = new MockAToken(Currency.unwrap(token0), "aToken0", "aToken0");
        console.log("3");
        MockAToken atoken1 = new MockAToken(Currency.unwrap(token1), "aToken1", "aToken1");

        console.log("4");
        MockAavePool aavePool = new MockAavePool(Currency.unwrap(token0), aToken0, Currency.unwrap(token1), atoken1);
        console.log("5");
        aavePoolAddressesProvider = address(new MockAavePoolAddressesProvider(address(aavePool)));

        console.log("6");
        _deployHookManager();
        _deployHook();

        // Store commonly used addresses
        token0Address = Currency.unwrap(token0);
        token1Address = Currency.unwrap(token1);
        aToken0Address = hook.aToken0();
        aToken1Address = hook.aToken1();

        // Fund test users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Give tokens to the pool manager
        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);

        // Give tokens to the test users
        deal(Currency.unwrap(token0), user1, initialTokenBalance, false);
        deal(Currency.unwrap(token1), user1, initialTokenBalance, false);
        deal(Currency.unwrap(token0), user2, initialTokenBalance * 2, false);
        deal(Currency.unwrap(token1), user2, initialTokenBalance * 2, false);
    }

    function _deployHookManager() internal virtual {
        vm.startPrank(admin);
        hookManager = new HookManager(address(manager), admin);
        vm.stopPrank();
    }

    function _deployCreate2() internal virtual {
        vm.startPrank(admin);
        deployCodeTo("Create2Impl.sol:Create2Impl", CREATE2_DEPLOYER);
        vm.stopPrank();
    }

    function _deployHook() internal virtual {
        vm.startPrank(admin);
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144); // Namespace the hook to avoid collisions

        ModularHookV1HookConfig memory hookParams = ModularHookV1HookConfig({
            poolManager: IPoolManager(manager),
            token0: token0,
            token1: token1,
            tickMin: tickMin,
            tickMax: tickMax,
            aavePoolAddressesProvider: aavePoolAddressesProvider,
            shareName: shareName,
            shareSymbol: shareSymbol,
            fee_bps: fee_bps,
            bufferSize0: bufferSize,
            bufferSize1: bufferSize,
            minTransferAmount0: minTransferAmount,
            minTransferAmount1: minTransferAmount
        });
        bytes memory constructorArgs = abi.encode(hookParams); //Add all the necessary constructor arguments from the hook
        bytes memory creationCode = abi.encodePacked(type(ModularHookV1).creationCode, constructorArgs);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(hookManager), flags, type(ModularHookV1).creationCode, constructorArgs);
        hookManager.deployHook(
            hookParams.token0, hookParams.token1, hookAddress, SQRT_PRICE_1_1, fee, tickSpacing, salt, creationCode
        ); // Deploy the hook using the hook manager
        hook = ModularHookV1(hookAddress);
        simpleKey =
            PoolKey({currency0: token0, currency1: token1, fee: fee, tickSpacing: tickSpacing, hooks: IHooks(hook)});
        // Set the pool ID
        simplePoolId = PoolId.wrap(keccak256(abi.encode(simpleKey)));
        vm.stopPrank();
    }

    // Helper function to get current token balances for any address
    function getBalances(address user) internal view returns (TokenBalances memory balances) {
        balances.userToken0 = IERC20(token0Address).balanceOf(user);
        balances.userToken1 = IERC20(token1Address).balanceOf(user);
        balances.hookToken0 = IERC20(token0Address).balanceOf(address(hook));
        balances.hookToken1 = IERC20(token1Address).balanceOf(address(hook));
        balances.hookAToken0 = IERC20(aToken0Address).balanceOf(address(hook));
        balances.hookAToken1 = IERC20(aToken1Address).balanceOf(address(hook));
    }

    // Helper function to get token amounts for a liquidity amount
    function getTokenAmountsForLiquidity(uint256 liquidity)
        internal
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        (int128 token0Delta, int128 token1Delta) = hook.getTokenAmountsForLiquidity(liquidity);
        token0Amount = token0Delta < 0 ? uint256(uint128(-token0Delta)) : 0;
        token1Amount = token1Delta < 0 ? uint256(uint128(-token1Delta)) : 0;
    }

    // Helper function to deposit liquidity for a specific user
    function depositLiquidity(address user, uint256 depositAmount)
        internal
        returns (
            uint256 token0Amount,
            uint256 token1Amount,
            TokenBalances memory before,
            TokenBalances memory afterBalances
        )
    {
        // Get token amounts for this liquidity
        (token0Amount, token1Amount) = getTokenAmountsForLiquidity(depositAmount);

        // Make sure user has enough tokens
        deal(token0Address, user, token0Amount, false);
        deal(token1Address, user, token1Amount, false);

        // Approve tokens
        vm.startPrank(user);
        IERC20(token0Address).approve(address(hook), token0Amount);
        IERC20(token1Address).approve(address(hook), token1Amount);

        // Get balances before deposit
        before = getBalances(user);

        // Deposit liquidity
        hook.deposit(depositAmount, user);
        vm.stopPrank();

        // Get balances after deposit
        afterBalances = getBalances(user);
    }

    // Helper function to compare share values between users
    function compareShareValues(address _user1, address _user2)
        internal
        view
        returns (uint256 user1ShareValue, uint256 user2ShareValue)
    {
        uint256 user1Shares = IERC20(address(hook)).balanceOf(_user1);
        uint256 user2Shares = IERC20(address(hook)).balanceOf(_user2);

        // Calculate share values based on hook.convertToAssets(shares)
        user1ShareValue = hook.convertToAssets(user1Shares);
        user2ShareValue = hook.convertToAssets(user2Shares);

        return (user1ShareValue, user2ShareValue);
    }
}
