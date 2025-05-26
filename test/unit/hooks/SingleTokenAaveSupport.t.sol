// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {HookV1Test} from "../HookV1.t.sol";
import {MockERC20} from "../../utils/mocks/MockERC20.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/*
  This test deploys a new hook where one token is supported by aave but the other is not.
  We need to verify that all main scenarios still work correctly with and without buffer
  1. Deposits
  2. Withdraws
  3. Swaps
*/
contract SingleTokenAaveSupportTest is HookV1Test {
    address token3 = address(0x1234567890123456789012345678901234567890); // Example unsupported token address

    function setUp() public virtual override {
        super.setUp();
        // deploy a new erc20 token that is not supported by aave and set it as contract variable
        token3 = address(new MockERC20("Unsupported Token", "UTK", 6));
        // deploy a new hook that will use this token and create a pool with it
        address lesserToken = Currency.unwrap(token0) < token3 ? Currency.unwrap(token0) : token3;
        address greaterToken = Currency.unwrap(token0) < token3 ? token3 : Currency.unwrap(token0);
        _deployHook(Currency.wrap(lesserToken), Currency.wrap(greaterToken));


        token0 = Currency.wrap(lesserToken);
        token1 = Currency.wrap(greaterToken);
        token0Address = lesserToken;
        token1Address = greaterToken;

        deal(Currency.unwrap(token0), address(manager), 1e18, false);
        deal(Currency.unwrap(token1), address(manager), 1e18, false);
        deal(Currency.unwrap(token0), address(this), 1e18, false);
        deal(Currency.unwrap(token1), address(this), 1e18, false);

        // Give tokens to the test users
        deal(Currency.unwrap(token0), user1, initialTokenBalance, false);
        deal(Currency.unwrap(token1), user1, initialTokenBalance, false);
        deal(Currency.unwrap(token0), user2, initialTokenBalance * 2, false);
        deal(Currency.unwrap(token1), user2, initialTokenBalance * 2, false);
        // to deploy new hook you need to update _deployHook function in BaseTest to allow specifying token addresses
    }

    // no need to implement actual test scenarios as they are inherited from HookV1Test

}
