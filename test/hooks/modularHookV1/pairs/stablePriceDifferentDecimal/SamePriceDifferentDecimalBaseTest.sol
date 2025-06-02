// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {ModularHookBaseTest} from "../../base/ModularHookBaseTest.sol";
import {ModularHookFeeAccrualTest} from "../../base/ModularHookFeeAccrual.t.sol";
import {ModularHookSwapTest} from "../../base/ModularHookSwap.t.sol";
import {ModularHookWithdrawalTest} from "../../base/ModularHookWithdrawal.t.sol";
import {ModularHookYieldAccrualTest} from "../../base/ModularHookYieldAccrual.t.sol";
import {ModularHookFeatureComboTest} from "../../base/ModularHookFeatureCombo.t.sol";

// SamePriceDifferentDecimalBaseTest test
// Serves as the foundation for all tests related to ModularHookV1
// Overrides the base setup methods to specifically configure for ModularHookV1 testing
contract SamePriceDifferentDecimalBaseTest is
    ModularHookBaseTest,
    ModularHookFeeAccrualTest,
    ModularHookSwapTest,
    ModularHookWithdrawalTest,
    ModularHookYieldAccrualTest,
    ModularHookFeatureComboTest
{
    function poolManagerInitialBalance0() internal virtual override returns (uint256) {
        return _poolManagerInitialBalance0 * 1e12;
    }

    function poolManagerInitialBalance1() internal virtual override returns (uint256) {
        return _poolManagerInitialBalance1;
    }

    function token0Decimals() internal virtual override returns (uint8) {
        return 18;
    }

    function token1Decimals() internal virtual override returns (uint8) {
        return 6;
    }

    function userInitialBalance0() internal virtual override returns (uint256) {
        return _userInitialBalance0 * 1e12;
    }

    function userInitialBalance1() internal virtual override returns (uint256) {
        return _userInitialBalance1;
    }

    function tickMin() internal virtual override returns (int24) {
        return TickMath.getTickAtSqrtPrice(initialPrice()) - 1;
    }

    function tickMax() internal virtual override returns (int24) {
        return TickMath.getTickAtSqrtPrice(initialPrice()) + 1;
    }

    function tickSpacing() internal virtual override returns (int24) {
        return _tickSpacing;
    }

    function bufferSize0() internal virtual override returns (uint256) {
        return _bufferSize0 * 1e12;
    }

    function bufferSize1() internal virtual override returns (uint256) {
        return _bufferSize1; // add 12 decimals
    }

    function minTransferAmount0() internal virtual override returns (uint256) {
        return _minTransferAmount0 * 1e12;
    }

    function minTransferAmount1() internal virtual override returns (uint256) {
        return _minTransferAmount1;
    }

    function initialPrice() internal virtual override returns (uint160) {
        return uint160(79224306130848112672356);
    }
}
