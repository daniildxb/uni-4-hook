// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactorCallback} from "@uniswapx/src/interfaces/IReactorCallback.sol";
import {SignedOrder, ResolvedOrder} from "@uniswapx/src/base/ReactorStructs.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IReactor} from "@uniswapx/src/interfaces/IReactor.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencySettler} from "v4-periphery/lib/v4-core/test/utils/CurrencySettler.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/*
// the flow is the following

1. Filler calls fillOrder
2. We call reactor
3. reactor calls callback1
4. in the callback1 we call swap
5. swap calls poolmanager
6. poolmanager calls callback2
7. in the callback2 we actually swap
8. and approve tokens to reactor

*/
contract UniswapXExecutor is IReactorCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20Metadata;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    IPoolManager public immutable manager;
    address private immutable whitelistedCaller;
    IReactor private immutable reactor;

    constructor(IPoolManager _manager, address _reactor, address _whitelistedCaller) {
        manager = _manager;
        whitelistedCaller = _whitelistedCaller;
        reactor = IReactor(_reactor);
    }

    struct OrderRoutingData {
        bytes32 poolId;
    }

    struct CallbackData {
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    //reverse mapping of poolId to PoolKey
    mapping(bytes32 => PoolKey) public poolKeys;
    
    // Function to register a pool key
    function registerPool(PoolKey calldata key) external onlyWhitelistedCaller {
        bytes32 poolId = PoolId.unwrap(key.toId());
        poolKeys[poolId] = key;
    }

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();

    // to ensure only our filler calls it
    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        _;
    }

    function fillOrder(SignedOrder calldata order, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeWithCallback(order, callbackData);
    }

    // input token has been transferred from reactor to us
    function reactorCallback(ResolvedOrder[] memory resolvedOrders, bytes memory callbackData) external onlyReactor {
        // receives orders from reactor
        // has to execute them and then approve the tokens to the reactor
        if (resolvedOrders.length != 1) {
            revert("Only single orders supported for now");
        }

        ResolvedOrder memory order = resolvedOrders[0];
        OrderRoutingData memory routingData = abi.decode(callbackData, (OrderRoutingData));

        PoolKey memory key = poolKeys[routingData.poolId];
        bool zeroForOne = true;
        if (address(order.input.token) != Currency.unwrap(key.currency0)) {
            zeroForOne = false;
        }

        // swap callback will be called by the router
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(order.input.amount),
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });

        // need to approve the input token to the router
        // and output token to the reactor
        // no need to approve the input token yet
        swap(key, params);
        // swap has been called and the tokens are now in the executor

        // transfer any native balance to the reactor
        // it will refund any excess
        for (uint256 i = 0; i < order.outputs.length; i++) {
            IERC20Metadata token = IERC20Metadata(order.outputs[i].token);
            if (address(token) == address(0)) {
                // native token
                continue;
            }
            // approve the token to the reactor
            token.forceApprove(address(reactor), type(uint256).max);
        }
        if (address(this).balance > 0) {
            _transferNative(address(reactor), address(this).balance);
        }
    }

    function swap(PoolKey memory key, IPoolManager.SwapParams memory params) internal {
        manager.unlock(abi.encode(CallbackData(key, params)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, new bytes(0));

        if (data.params.zeroForOne) {
            data.key.currency0.settle(manager, address(this), uint256(int256(-delta.amount0())), false);
            data.key.currency1.take(manager, address(this), uint256(int256(delta.amount1())), false);
        } else {
            data.key.currency1.settle(manager, address(this), uint256(int256(-delta.amount1())), false);
            data.key.currency0.take(manager, address(this), uint256(int256(delta.amount0())), false);
        }

        return "";
    }

    /// @notice Transfer native currency to recipient
    /// @param recipient The recipient of the currency
    /// @param amount The amount of currency to transfer
    function _transferNative(address recipient, uint256 amount) internal {
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert("Native transfer failed");
    }
}
