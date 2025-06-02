// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {ERC20} from "@solmate-unix/src/tokens/ERC20.sol";

import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {ModularHookV1} from "../../../src/ModularHookV1.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BaseTest} from "../../BaseTest.sol";
import {DeployPermit2} from "../../utils/DeployPermit2.sol";
import {UniswapXExecutor} from "../../../src/UniswapXExecutor.sol";
import {IReactor} from "@uniswapx/src/interfaces/IReactor.sol";
import {PriorityOrderReactor} from "@uniswapx/src/reactors/PriorityOrderReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken} from "@uniswapx/src/base/ReactorStructs.sol";
import {
    PriorityOrder, PriorityInput, PriorityOutput, PriorityCosignerData
} from "@uniswapx/src/lib/PriorityOrderLib.sol";
import {OrderInfoBuilder} from "@uniswapx/test/util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "@uniswapx/test/util/OutputsBuilder.sol";
import {PermitSignature} from "@uniswapx/test/util/PermitSignature.sol";
import {PriorityOrderLib} from "@uniswapx/src/lib/PriorityOrderLib.sol";
import {CosignerLib} from "@uniswapx/src/lib/CosignerLib.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract ExecutorTest is BaseTest, DeployPermit2, PermitSignature {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using OrderInfoBuilder for OrderInfo;
    using PriorityOrderLib for PriorityOrder;
    using PoolIdLibrary for PoolId;

    uint256 hookDepositAmounts = 1000 * 1e6;
    UniswapXExecutor executor;
    PriorityOrderReactor priorityReactor;
    IPermit2 permit2;

    uint256 constant ONE = 10 ** 18;
    uint256 swapperPrivateKey;
    address swapper;
    uint256 cosignerPrivateKey;
    address cosigner;

    address constant PROTOCOL_FEE_OWNER = address(0x8c3D9A0312890527afc6aE4Ee16Ca263Fbb0dCCd);
    address constant weth = address(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);

    // ensuring hook and pool manager has some liquidity
    function setUp() public virtual override {
        super.setUp();

        // Setup test accounts
        swapperPrivateKey = 0x1234;
        swapper = vm.addr(swapperPrivateKey);
        cosignerPrivateKey = 0x5678;
        cosigner = vm.addr(cosignerPrivateKey);

        // Provide liquidity to the pool
        deal(Currency.unwrap(token0), address(user1), hookDepositAmounts);
        deal(Currency.unwrap(token1), address(user1), hookDepositAmounts);
        depositTokensToHook(hookDepositAmounts, hookDepositAmounts, user1);

        // Deploy the UniswapX periphery
        _deployPeriphery();

        // Register the pool key with executor for routing
        executor.poolKeys(PoolId.unwrap(simplePoolId)); // This will revert since the key isn't registered yet

        // Register the pool key with executor
        vm.prank(address(this));
        executor.registerPool(simpleKey);

        // Fund swapper with tokens
        deal(Currency.unwrap(token0), swapper, ONE * 10);
        deal(Currency.unwrap(token1), swapper, ONE * 10);

        // Approve tokens to permit2
        vm.startPrank(swapper);
        IERC20(Currency.unwrap(token0)).approve(address(permit2), type(uint256).max);
        IERC20(Currency.unwrap(token1)).approve(address(permit2), type(uint256).max);
        vm.stopPrank();
    }

    function _deployPeriphery() internal {
        // Deploy Permit2
        permit2 = IPermit2(deployPermit2());

        // Deploy PriorityOrderReactor
        priorityReactor = new PriorityOrderReactor(permit2, PROTOCOL_FEE_OWNER);

        // Deploy UniswapXExecutor
        executor = new UniswapXExecutor(address(manager), address(priorityReactor), address(this), weth, address(this));
    }

    function test_registerPool() public {
        bytes32 poolId = PoolId.unwrap(simplePoolId);
        (Currency token0, Currency token1, uint24 fee, int24 tickSpacing, IHooks hooks) = executor.poolKeys(poolId);
        PoolKey memory key =
            PoolKey({currency0: token0, currency1: token1, fee: fee, tickSpacing: tickSpacing, hooks: hooks});

        // Verify the pool key is registered correctly
        assertEq(Currency.unwrap(key.currency0), Currency.unwrap(token0));
        assertEq(Currency.unwrap(key.currency1), Currency.unwrap(token1));
        assertEq(key.fee, fee);
        assertEq(key.tickSpacing, tickSpacing);
        assertEq(address(key.hooks), address(hook));
    }

    function test_fillSwapOrderZeroForOne() public {
        // Create PriorityOrder (token0 -> token1)
        uint256 inputAmount = 1e6; // 0.1 token0
        uint256 outputAmount = 9e5; // Expecting to receive at least 0.09 token1
        uint256 deadline = block.timestamp + 1000;

        PriorityOutput[] memory outputs =
            OutputsBuilder.singlePriority(Currency.unwrap(token1), outputAmount, 0, swapper);

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(priorityReactor)).withSwapper(swapper).withDeadline(deadline),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({
                token: ERC20(address(Currency.unwrap(token0))),
                amount: inputAmount,
                mpsPerPriorityFeeWei: 0
            }),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(inputAmount),
            sqrtPriceLimitX96: 4295128740
        });

        // Prepare order routing data
        UniswapXExecutor.OrderRoutingData memory routingData =
            UniswapXExecutor.OrderRoutingData({poolId: PoolId.unwrap(simplePoolId), params: params});

        // Sign order
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // Record balances before swap
        uint256 swapperToken0Before = IERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 swapperToken1Before = IERC20(Currency.unwrap(token1)).balanceOf(swapper);

        // Execute order with routing data
        vm.prank(address(this));
        executor.execute(signedOrder, abi.encode(routingData));

        // Check balances after swap
        uint256 swapperToken0After = IERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 swapperToken1After = IERC20(Currency.unwrap(token1)).balanceOf(swapper);

        // Verify tokens were correctly transferred
        assertEq(swapperToken0Before - swapperToken0After, inputAmount, "Incorrect input amount spent");
        assertTrue(swapperToken1After > swapperToken1Before, "No output tokens received");
        assertTrue(swapperToken1After - swapperToken1Before >= outputAmount, "Not enough output tokens received");
    }

    function test_fillSwapOrderOneForZero() public {
        // Create PriorityOrder (token1 -> token0)
        uint256 inputAmount = 1e6; // 0.1 token1
        uint256 outputAmount = 9e5; // Expecting to receive at least 0.09 token0
        uint256 deadline = block.timestamp + 1000;

        PriorityOutput[] memory outputs =
            OutputsBuilder.singlePriority(Currency.unwrap(token0), outputAmount, 0, swapper);

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(priorityReactor)).withSwapper(swapper).withDeadline(deadline).withNonce(1), // Use a different nonce
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: ERC20(Currency.unwrap(token1)), amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(inputAmount),
            sqrtPriceLimitX96: 7922816251426433759354395033600000
        });

        // Prepare order routing data
        UniswapXExecutor.OrderRoutingData memory routingData =
            UniswapXExecutor.OrderRoutingData({poolId: PoolId.unwrap(simplePoolId), params: params});

        // Sign order
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // Record balances before swap
        uint256 swapperToken0Before = IERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 swapperToken1Before = IERC20(Currency.unwrap(token1)).balanceOf(swapper);

        // Execute order with routing data
        vm.prank(address(this));
        executor.execute(signedOrder, abi.encode(routingData));

        // Check balances after swap
        uint256 swapperToken0After = IERC20(Currency.unwrap(token0)).balanceOf(swapper);
        uint256 swapperToken1After = IERC20(Currency.unwrap(token1)).balanceOf(swapper);

        // Verify tokens were correctly transferred
        assertEq(swapperToken1Before - swapperToken1After, inputAmount, "Incorrect input amount spent");
        assertTrue(swapperToken0After > swapperToken0Before, "No output tokens received");
        assertTrue(swapperToken0After - swapperToken0Before >= outputAmount, "Not enough output tokens received");
    }

    function test_reverWhen_not_enough_liquidity() public {
        // Create PriorityOrder (token1 -> token0)
        uint256 inputAmount = 1e12; // 0.1 token1
        uint256 outputAmount = 9e11; // Expecting to receive at least 0.09 token0
        uint256 deadline = block.timestamp + 1000;

        PriorityOutput[] memory outputs =
            OutputsBuilder.singlePriority(Currency.unwrap(token0), outputAmount, 0, swapper);

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(priorityReactor)).withSwapper(swapper).withDeadline(deadline).withNonce(1), // Use a different nonce
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: ERC20(Currency.unwrap(token1)), amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(inputAmount), sqrtPriceLimitX96: 0});

        // Prepare order routing data
        UniswapXExecutor.OrderRoutingData memory routingData =
            UniswapXExecutor.OrderRoutingData({poolId: PoolId.unwrap(simplePoolId), params: params});

        // Sign order
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // Execute order with routing data
        vm.prank(address(this));
        vm.expectRevert();
        executor.execute(signedOrder, abi.encode(routingData));
    }

    function test_revertWhen_InvalidCaller() public {
        // Create a simple order
        uint256 inputAmount = 1e6;
        uint256 outputAmount = 9e5;
        uint256 deadline = block.timestamp + 1000;

        PriorityOutput[] memory outputs =
            OutputsBuilder.singlePriority(Currency.unwrap(token1), outputAmount, 0, swapper);

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(priorityReactor)).withSwapper(swapper).withDeadline(deadline).withNonce(2),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: ERC20(Currency.unwrap(token0)), amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(inputAmount), sqrtPriceLimitX96: 0});

        // Prepare order routing data
        UniswapXExecutor.OrderRoutingData memory routingData =
            UniswapXExecutor.OrderRoutingData({poolId: PoolId.unwrap(simplePoolId), params: params});

        // Sign order
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // Try to call with a non-whitelisted address
        vm.prank(address(0xBAD));
        vm.expectRevert(UniswapXExecutor.CallerNotWhitelisted.selector);
        executor.execute(signedOrder, abi.encode(routingData));
    }

    function test_revertWhen_InvalidPoolId() public {
        // Create a simple order
        uint256 inputAmount = 1e6;
        uint256 outputAmount = 9e5;
        uint256 deadline = block.timestamp + 1000;

        PriorityOutput[] memory outputs =
            OutputsBuilder.singlePriority(Currency.unwrap(token1), outputAmount, 0, swapper);

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(priorityReactor)).withSwapper(swapper).withDeadline(deadline).withNonce(3),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: ERC20(Currency.unwrap(token0)), amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        IPoolManager.SwapParams memory params =
            IPoolManager.SwapParams({zeroForOne: false, amountSpecified: -int256(inputAmount), sqrtPriceLimitX96: 0});

        // Prepare order routing data with invalid pool ID
        bytes32 invalidPoolId = keccak256("invalid_pool_id");
        UniswapXExecutor.OrderRoutingData memory routingData =
            UniswapXExecutor.OrderRoutingData({poolId: invalidPoolId, params: params});

        // Sign order
        order.cosignature = cosignOrder(order.hash(), cosignerData);
        SignedOrder memory signedOrder =
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey, address(permit2), order));

        // Execute should revert because the pool key is not registered
        vm.prank(address(this));
        vm.expectRevert(); // Will revert when trying to access an unregistered pool key
        executor.execute(signedOrder, abi.encode(routingData));
    }

    // Helper function to sign cosigner data
    function cosignOrder(bytes32 orderHash, PriorityCosignerData memory cosignerData)
        private
        view
        returns (bytes memory sig)
    {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    // Add a function to register a pool with the executor
    function registerPool(PoolKey memory key) external {
        executor.registerPool(key);
    }
}
