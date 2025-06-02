// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {HookManager} from "src/HookManager.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {ModularHookV1} from "src/ModularHookV1.sol";
import {BaseTest} from "../../../BaseTest.sol";

// Base Test for ModularHookV1 tests
// Serves as the foundation for all tests related to ModularHookV1
// Overrides the base setup methods to specifically configure for ModularHookV1 testing
contract ModularHookBaseTest is BaseTest {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SafeERC20 for IERC20;
    using BalanceDeltaLibrary for BalanceDelta;

    // Constants for testing
    address public allowedUser = address(777);
    address public nonAllowedUser = address(888);

    // Override the hook deployment method if needed
    // (Not required if the BaseTest implementation is sufficient)

    // Additional utility functions specific to ModularHookV1 testing

    /**
     * @notice Helper for setting up allowlist feature
     * @param allowlistEnabled Whether to enable the allowlist
     * @param userToAllow Address to add to the allowlist (if any)
     */
    function setupAllowlist(bool allowlistEnabled, address userToAllow) internal {
        vm.startPrank(address(hookManager));

        if (allowlistEnabled) {
            ModularHookV1(address(hook)).flipAllowlist();

            if (userToAllow != address(0)) {
                ModularHookV1(address(hook)).flipAddressInAllowList(userToAllow);
            }
        }

        vm.stopPrank();
    }

    /**
     * @notice Helper for setting deposit caps
     * @param cap0 Deposit cap for token0
     * @param cap1 Deposit cap for token1
     */
    function setupDepositCaps(uint256 cap0, uint256 cap1) internal {
        vm.startPrank(address(hookManager));
        ModularHookV1(address(hook)).setDepositCaps(cap0, cap1);
        vm.stopPrank();
    }

    /**
     * @notice Verify the hook state after operations
     * @return totalAssets Current total assets in the hook
     * @return totalSupply Current total supply of shares
     */
    function verifyHookState() internal view returns (uint256 totalAssets, uint256 totalSupply) {
        totalAssets = hook.totalAssets();
        totalSupply = IERC20(address(hook)).totalSupply();

        console.log("Hook State:");
        console.log("- Total Assets:", totalAssets);
        console.log("- Total Supply:", totalSupply);
        console.log("- Token0 Balance:", IERC20(token0Address).balanceOf(address(hook)));
        console.log("- Token1 Balance:", IERC20(token1Address).balanceOf(address(hook)));

        return (totalAssets, totalSupply);
    }

    /**
     * @notice Execute a swap to test swap-related functionality
     * @param zeroForOne Direction of the swap
     * @param amountSpecified Amount to swap (negative for exact input)
     * @return swapDelta The balance delta resulting from the swap
     */
    function executeSwap(bool zeroForOne, int256 amountSpecified) internal returns (BalanceDelta swapDelta) {
        // Approve tokens for swap
        address tokenIn = zeroForOne ? Currency.unwrap(token0) : Currency.unwrap(token1);
        IERC20(tokenIn).forceApprove(address(swapRouter), uint256(-amountSpecified));

        // Execute the swap
        swapDelta = swap(simpleKey, zeroForOne, amountSpecified, bytes(""));

        console.log("Swap Results:");
        console.log("- Delta Amount0:", swapDelta.amount0());
        console.log("- Delta Amount1:", swapDelta.amount1());

        return swapDelta;
    }
}
