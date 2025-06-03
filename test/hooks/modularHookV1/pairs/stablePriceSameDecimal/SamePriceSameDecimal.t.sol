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

// SamePriceSameDecimalBaseTest test
// Overrides the base setup methods to specifically configure for ModularHookV1 testing
// base test use 6 decimals for both token so we don't need to override
contract SamePriceSameDecimalBaseTest is
    ModularHookBaseTest,
    ModularHookFeeAccrualTest,
    ModularHookSwapTest,
    ModularHookWithdrawalTest,
    ModularHookYieldAccrualTest,
    ModularHookFeatureComboTest
{}
