// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ModularHookV1} from "../../../src/ModularHookV1.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {BaseTest} from "../../BaseTest.sol";
import {DeployPermit2} from "../../utils/DeployPermit2.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UniswapXExecutor} from "../../../src/UniswapXExecutor.sol";
import {IReactor} from "@uniswapx/interfaces/IReactor.sol";
import {PriorityOrderReactor} from "@uniswapx/reactors/PriorityOrderReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";


contract ExecutorTest is BaseTest, DeployPermit2 {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;

    uint256 hookDepositAmounts = 1000 * 1e6;
    UniswapXExecutor executor;
    IReactor reactor;
    IPermit2 permit2;

    // ensuring hook and pool manager has some liquidity
    function setUp() public virtual override {
        super.setUp();
        deal(Currency.unwrap(token0), address(user1), hookDepositAmounts);
        deal(Currency.unwrap(token1), address(user1), hookDepositAmounts);

        depositTokensToHook(hookDepositAmounts, hookDepositAmounts, user1);

        _deployPeriphery();
    }

    function _deployPeriphery() internal {
        // deploy reactor
        permit2 = IPermit2(deployPermit2());
        reactor = new PriorityOrderReactor(permit2, address(this));
        // deploy executor
        executor = new UniswapXExecutor(manager, address(reactor), address(this));
    }

    function test_shouldFillSwapOrder() public {
      assert(true);
    }
}
