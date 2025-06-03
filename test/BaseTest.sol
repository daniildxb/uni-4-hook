// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
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
    int24 _tickMin = -2;
    int24 _tickMax = 2;
    address aavePoolAddressesProvider;
    string shareName = "name";
    string shareSymbol = "symbol";
    HookManager hookManager;
    ModularHookV1 hook; // Changed from HookV1 to ModularHookV1
    uint24 fee = 3000;
    int24 _tickSpacing = 1;
    uint256 fee_bps = 10; // 0.0001%
    uint256 _bufferSize0 = 1e7;
    uint256 _bufferSize1 = 1e7;
    uint256 _minTransferAmount0 = 1e6;
    uint256 _minTransferAmount1 = 1e6;
    uint256 _poolManagerInitialBalance0 = 1e18; // Initial balance for the pool manager
    uint256 _poolManagerInitialBalance1 = 1e18; // Initial balance for the pool manager
    uint256 _userInitialBalance0 = 1e12; // Initial balance for the pool manager
    uint256 _userInitialBalance1 = 1e12; // Initial balance for the pool manager

    address admin = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    address initialDepositor = address(0xdead);

    PoolKey simpleKey; // vanilla pool key
    PoolId simplePoolId; // id for vanilla pool key

    // Test accounts
    address public user1 = address(777);
    address public user2 = address(888);

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
        deployFreshManagerAndRouters();
        (token0, token1) = _deployMintAndApprove2Currencies();
        _deployCreate2();

        MockAToken aToken0 = new MockAToken(Currency.unwrap(token0), "aToken0", "aToken0", token0Decimals());
        MockAToken atoken1 = new MockAToken(Currency.unwrap(token1), "aToken1", "aToken1", token1Decimals());

        MockAavePool aavePool = new MockAavePool(Currency.unwrap(token0), aToken0, Currency.unwrap(token1), atoken1);
        aavePoolAddressesProvider = address(new MockAavePoolAddressesProvider(address(aavePool)));

        _deployHookManager();
        _deployHook(token0, token1);

        // Store commonly used addresses
        token0Address = Currency.unwrap(token0);
        token1Address = Currency.unwrap(token1);
        aToken0Address = hook.aToken0();
        aToken1Address = hook.aToken1();
        _doInitialDeposit();

        // Fund test users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Give tokens to the pool manager
        console.log("Funding pool manager with initial balances");
        deal(Currency.unwrap(token0), address(manager), poolManagerInitialBalance0(), false);
        deal(Currency.unwrap(token1), address(manager), poolManagerInitialBalance1(), false);

        // Give tokens to the test users
        console.log("Funding test users with initial balances");
        deal(Currency.unwrap(token0), user1, userInitialBalance0(), false);
        deal(Currency.unwrap(token1), user1, userInitialBalance1(), false);
        deal(Currency.unwrap(token0), user2, userInitialBalance0() * 2, false);
        deal(Currency.unwrap(token1), user2, userInitialBalance1() * 2, false);
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

    function poolManagerInitialBalance0() internal virtual returns (uint256) {
        return _poolManagerInitialBalance0;
    }

    function poolManagerInitialBalance1() internal virtual returns (uint256) {
        return _poolManagerInitialBalance1;
    }

    function userInitialBalance0() internal virtual returns (uint256) {
        return _userInitialBalance0;
    }

    function userInitialBalance1() internal virtual returns (uint256) {
        return _userInitialBalance1;
    }

    function tickMin() internal virtual returns (int24) {
        return _tickMin;
    }

    function tickMax() internal virtual returns (int24) {
        return _tickMax;
    }

    function tickSpacing() internal virtual returns (int24) {
        return _tickSpacing;
    }

    function bufferSize0() internal virtual returns (uint256) {
        return _bufferSize0;
    }

    function bufferSize1() internal virtual returns (uint256) {
        return _bufferSize1;
    }

    function minTransferAmount0() internal virtual returns (uint256) {
        return _minTransferAmount0;
    }

    function minTransferAmount1() internal virtual returns (uint256) {
        return _minTransferAmount1;
    }

    function initialPrice() internal virtual returns (uint160) {
        return SQRT_PRICE_1_1;
    }

    function token0Decimals() internal virtual returns (uint8) {
        return 6; // Default decimals for USDC
    }

    function token1Decimals() internal virtual returns (uint8) {
        return 6; // Default decimals for USDC
    }

    // for some stupid reason it auto converted to uint8 without explicit cast
    function depositAmount0() internal virtual returns (uint256) {
        return scaleToken0Amount(100);
    }

    function depositAmount1() internal virtual returns (uint256) {
        return scaleToken1Amount(100);
    }

    function scaleToken0Amount(uint256 amount) internal virtual returns (uint256) {
        return amount * (10 ** token0Decimals());
    }

    function scaleToken1Amount(uint256 amount) internal virtual returns (uint256) {
        return amount * (10 ** token1Decimals());
    }

    function _doInitialDeposit() internal virtual {
        // Initial deposit to the hook
        uint256 token0Amount = depositAmount0() * 100;
        uint256 token1Amount = depositAmount1() * 100;
        deal(token0Address, initialDepositor, token0Amount, false);
        deal(token1Address, initialDepositor, token1Amount, false);
        depositTokensToHook(token0Amount, token1Amount, initialDepositor);
    }

    function _deployHook(Currency _token0, Currency _token1) internal virtual {
        vm.startPrank(admin);
        uint160 flags =
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG) ^ (0x4444 << 144); // Namespace the hook to avoid collisions

        ModularHookV1HookConfig memory hookParams = ModularHookV1HookConfig({
            poolManager: IPoolManager(manager),
            token0: _token0,
            token1: _token1,
            tickMin: tickMin(),
            tickMax: tickMax(),
            aavePoolAddressesProvider: aavePoolAddressesProvider,
            shareName: shareName,
            shareSymbol: shareSymbol,
            fee_bps: fee_bps,
            bufferSize0: bufferSize0(),
            bufferSize1: bufferSize1(),
            minTransferAmount0: minTransferAmount0(),
            minTransferAmount1: minTransferAmount1()
        });
        bytes memory constructorArgs = abi.encode(hookParams); //Add all the necessary constructor arguments from the hook
        bytes memory creationCode = abi.encodePacked(type(ModularHookV1).creationCode, constructorArgs);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(hookManager), flags, type(ModularHookV1).creationCode, constructorArgs);
        hookManager.deployHook(
            hookParams.token0, hookParams.token1, hookAddress, initialPrice(), fee, tickSpacing(), salt, creationCode
        ); // Deploy the hook using the hook manager
        hook = ModularHookV1(hookAddress);
        simpleKey =
            PoolKey({currency0: _token0, currency1: _token1, fee: fee, tickSpacing: tickSpacing(), hooks: IHooks(hook)});
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
        hook.deposit(depositAmount, user, ZERO_BYTES);
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

    function depositTokensToHook(uint256 token0Amount, uint256 token1Amount, address receiver)
        internal
        returns (uint256 shares, uint128 liquidity, int128 amount0, int128 amount1)
    {
        console.log("Depositing tokens to hook:", token0Amount, token1Amount);
        (liquidity, amount0, amount1) = hook.getLiquidityForTokenAmounts(token0Amount, token1Amount);
        console.log("liquidity deposited", liquidity);
        vm.startPrank(receiver);
        IERC20(token0Address).approve(address(hook), token0Amount);
        IERC20(token1Address).approve(address(hook), token1Amount);
        shares = hook.deposit(liquidity, receiver, ZERO_BYTES);
        vm.stopPrank();
        amount0 = amount0 < 0 ? -amount0 : amount0;
        amount1 = amount1 < 0 ? -amount1 : amount1;
        console.log("Deposited tokens to hook:", uint256(int256(amount0)), uint256(int256(amount1)));
    }

    function depositTokensToHookExpectRevert(uint256 token0Amount, uint256 token1Amount, address receiver) internal {
        console.log("Depositing tokens to hook:", token0Amount, token1Amount);
        (uint256 liquidity,,) = hook.getLiquidityForTokenAmounts(token0Amount, token1Amount);
        vm.startPrank(receiver);
        IERC20(token0Address).approve(address(hook), token0Amount);
        IERC20(token1Address).approve(address(hook), token1Amount);
        vm.expectRevert();
        hook.deposit(liquidity, receiver, ZERO_BYTES);
        vm.stopPrank();
    }

    function depositTokensToHookExpectRevert(
        uint256 token0Amount,
        uint256 token1Amount,
        address receiver,
        bytes4 message
    ) internal {
        (uint256 liquidity,,) = hook.getLiquidityForTokenAmounts(token0Amount, token1Amount);
        vm.startPrank(receiver);
        IERC20(token0Address).approve(address(hook), token0Amount);
        IERC20(token1Address).approve(address(hook), token1Amount);
        vm.expectRevert(message);
        hook.deposit(liquidity, receiver, ZERO_BYTES);
        vm.stopPrank();
    }

    function withdrawTokensFromHook(uint256 token0Amount, uint256 token1Amount, address receiver)
        internal
        returns (uint256 shares, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        uint256 token0BalanceBefore = IERC20(token0Address).balanceOf(receiver);
        uint256 token1BalanceBefore = IERC20(token1Address).balanceOf(receiver);
        (liquidity,,) = hook.getLiquidityForTokenAmounts(token0Amount, token1Amount);
        uint256 sharesToExit = hook.convertToShares(liquidity);
        vm.startPrank(receiver);
        shares = hook.redeem(sharesToExit, receiver, receiver);
        vm.stopPrank();

        uint256 token0BalanceAfter = IERC20(token0Address).balanceOf(receiver);
        uint256 token1BalanceAfter = IERC20(token1Address).balanceOf(receiver);

        amount0 = token0BalanceAfter - token0BalanceBefore;
        amount1 = token1BalanceAfter - token1BalanceBefore;
    }

    function _deployMintAndApprove2Currencies() internal virtual returns (Currency, Currency) {
        Currency _currencyA = deployMintAndApproveCurrency(token0Decimals());
        Currency _currencyB = deployMintAndApproveCurrency(token1Decimals());

        (currency0, currency1) =
            SortTokens.sort(MockERC20(Currency.unwrap(_currencyA)), MockERC20(Currency.unwrap(_currencyB)));
        return (currency0, currency1);
    }

    function deployMintAndApproveCurrency(uint8 decimals) internal returns (Currency currency) {
        MockERC20 token = deployTokens(1, 2 ** 255, decimals)[0];

        address[9] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor()),
            address(actionsRouter)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], type(uint256).max);
        }

        return Currency.wrap(address(token));
    }

    function deployTokens(uint8 count, uint256 totalSupply, uint8 decimals)
        internal
        returns (MockERC20[] memory tokens)
    {
        tokens = new MockERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new MockERC20("TEST", "TEST", decimals);
            tokens[i].mint(address(this), totalSupply);
        }
    }
}
