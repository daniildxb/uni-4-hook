// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {ModularHookBaseTest} from "../../base/ModularHookBaseTest.sol";
import {ModularHookFeeAccrualTest} from "../../base/ModularHookFeeAccrual.t.sol";
import {ModularHookSwapTest} from "../../base/ModularHookSwap.t.sol";
import {ModularHookWithdrawalTest} from "../../base/ModularHookWithdrawal.t.sol";
import {ModularHookYieldAccrualTest} from "../../base/ModularHookYieldAccrual.t.sol";
import {ModularHookFeatureComboTest} from "../../base/ModularHookFeatureCombo.t.sol";

// SamePriceDifferentDecimalBaseTest test
// Serves as the foundation for all tests related to ModularHookV1
// Overrides the base setup methods to specifically configure for ModularHookV1 testing
contract VariablePriceDifferentDecimalBaseTest is
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
        return _userInitialBalance0 * 1e12 * 2;
    }

    function userInitialBalance1() internal virtual override returns (uint256) {
        return _userInitialBalance1;
    }

    function tickMin() internal virtual override returns (int24) {
        return -887220;
    }

    function tickMax() internal virtual override returns (int24) {
        return 887220;
    }

    function tickSpacing() internal virtual override returns (int24) {
        return 60;
    }

    function bufferSize0() internal virtual override returns (uint256) {
        return _bufferSize0 * 1e12 * 2;
    }

    function bufferSize1() internal virtual override returns (uint256) {
        return _bufferSize1; // add 12 decimals
    }

    function minTransferAmount0() internal virtual override returns (uint256) {
        return _minTransferAmount0 * 1e12 * 2;
    }

    function minTransferAmount1() internal virtual override returns (uint256) {
        return _minTransferAmount1;
    }

    function initialPrice() internal virtual override returns (uint160) {
        // aproximately 2.4 : 1 with 18/6 decimals
        return uint160(123071741410724755212216);
    }

    function scaleToken0Amount(uint256 amount) internal virtual override returns (uint256) {
        return amount * (10 ** token0Decimals()) * 2;
    }

    function scaleToken1Amount(uint256 amount) internal virtual override returns (uint256) {
        return amount * (10 ** token1Decimals());
    }
}
