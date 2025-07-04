// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import "forge-std/console.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SwapRouterNoChecks} from "v4-core/src/test/SwapRouterNoChecks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "v4-periphery/lib/v4-core/test/utils/CurrencySettler.sol";

// todo: initial version of the contract will only support a single pool
// this is done for simplicity and verifying PoC
// ideally we would reuse the same contract for all hooks and arbitrage sources (v3 / v4)
contract UniswapArbitrager is Ownable {
    using SafeERC20 for IERC20Metadata;
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for *;
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    IPoolManager public immutable manager;
    address swapper;
    PoolKey keyYf;
    PoolKey keyUni;
    SwapRouterNoChecks swapRouter;

    struct CallbackData {
        address sender;
        PoolKey key0;
        PoolKey key1;
        IPoolManager.SwapParams params;
    }

    constructor(
        address _manager,
        address _swapper,
        address _owner,
        address _swapRouter,
        PoolKey memory _poolKeyYf,
        PoolKey memory _poolKeyUni
    ) Ownable(_owner) {
        manager = IPoolManager(_manager);
        swapper = _swapper;
        swapRouter = SwapRouterNoChecks(_swapRouter);
        keyYf = _poolKeyYf;
        keyUni = _poolKeyUni;
    }

    modifier onlySwapper() {
        require(msg.sender == swapper, "not allowed");
        _;
    }

    /**
     * @param isYfUni indicates direction of the swap
     * @param isZeroForOne indicated asset for the first swap
     * @param amount indicates exact amount for first swap
     * @return profit contains profit and output of the second swap
     */
    //
    function swap(bool isYfUni, bool isZeroForOne, uint256 amount) external onlySwapper returns (uint256 profit) {
        (PoolKey memory firstPool, PoolKey memory secondPool) = isYfUni ? (keyYf, keyUni) : (keyUni, keyYf);
        profit = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData(
                        msg.sender,
                        firstPool,
                        secondPool,
                        IPoolManager.SwapParams({
                            zeroForOne: isZeroForOne,
                            amountSpecified: -int256(amount),
                            sqrtPriceLimitX96: isZeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
                        })
                    )
                )
            ),
            (uint256)
        );
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        // First swap in pool 1
        BalanceDelta delta1 = manager.swap(data.key0, data.params, new bytes(0));

        // Use correct output amount from first swap based on direction
        int128 firstSwapOutput = data.params.zeroForOne ? delta1.amount1() : delta1.amount0();

        // Only proceed with second swap if we got a positive output
        require(firstSwapOutput > 0, "No output from first swap");

        // Second swap in pool 2 - use the output as exact input
        BalanceDelta delta2 = manager.swap(
            data.key1,
            IPoolManager.SwapParams({
                zeroForOne: !data.params.zeroForOne,
                amountSpecified: -firstSwapOutput, // Negative for exact input
                sqrtPriceLimitX96: !data.params.zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            new bytes(0)
        );

        // Calculate net result
        BalanceDelta finalDelta = delta1 + delta2;

        uint256 profit = 0;
        // Simple settlement - just settle what we owe and take what we're owed
        console.log("Final delta");
        console.log(finalDelta.amount0());
        console.log(finalDelta.amount1());
        if (finalDelta.amount0() != 0) {
            if (finalDelta.amount0() < 0) {
                // should never happen
                data.key0.currency0.settle(manager, data.sender, uint256(uint128(-finalDelta.amount0())), false);
            } else {
                // We are owed token0
                profit = uint256(uint128(finalDelta.amount0()));
                data.key0.currency0.take(manager, data.sender, profit, false);
            }
        }

        if (finalDelta.amount1() != 0) {
            if (finalDelta.amount1() < 0) {
                // We owe token1
                data.key0.currency1.settle(manager, data.sender, uint256(uint128(-finalDelta.amount1())), false);
            } else {
                // We are owed token1
                profit = uint256(uint128(finalDelta.amount1()));
                data.key0.currency1.take(manager, data.sender, uint256(uint128(profit)), false);
            }
        }

        return abi.encode(profit);
    }
}
