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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/*
// the flow is the following

1. Filler calls execute
2. We call reactor
3. reactor calls callback1
4. in the callback1 we call swap
5. swap calls poolmanager
6. poolmanager calls callback2
7. in the callback2 we actually swap
8. and approve tokens to reactor
*/

contract UniswapXExecutor is IReactorCallback, Ownable {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20Metadata;

    WETH private immutable weth;

    using SafeTransferLib for ERC20;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    IPoolManager public immutable manager;
    address private immutable whitelistedCaller;
    IReactor private immutable reactor;

    // _whitelistedCaller is the address of the filler
    // _owner is HookManager
    constructor(address _manager, address _reactor, address _whitelistedCaller, address _weth, address _owner)
        Ownable(_owner)
    {
        manager = IPoolManager(_manager);
        whitelistedCaller = _whitelistedCaller;
        reactor = IReactor(_reactor);
        weth = WETH(payable(_weth));
    }

    struct OrderRoutingData {
        bytes32 poolId;
        IPoolManager.SwapParams params;
    }

    struct CallbackData {
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    //reverse mapping of poolId to PoolKey
    mapping(bytes32 => PoolKey) public poolKeys;

    // Function to register a pool key
    function registerPool(PoolKey calldata key) external onlyOwner {
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

    function execute(SignedOrder calldata order, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeWithCallback(order, callbackData);
    }

    function executeBatch(SignedOrder[] calldata orders, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeBatchWithCallback(orders, callbackData);
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

        // need to approve the input token to the router
        // and output token to the reactor
        // no need to approve the input token yet
        swap(key, routingData.params);
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

    /// @notice Unwraps the contract's WETH9 balance and sends it to the recipient as ETH. Can only be called by owner.
    /// @param recipient The address receiving ETH
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balanceWETH = weth.balanceOf(address(this));

        weth.withdraw(balanceWETH);
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}

    function rescue(address token, uint256 amount, address to) external onlyOwner {
        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            ERC20(token).safeTransfer(to, amount);
        }
    }
}
