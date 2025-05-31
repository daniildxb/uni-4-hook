// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {RescueHook} from "../../../src/hooks/RescueHook.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Test for the rescue hook functionality
 */
contract ShareIssuanceTest is BaseTest {
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    function setUp() public override {
        super.setUp();
    }

    function test_donation_attack_isnot_viable() public {
        // attacker deposits into the pool
        // he then donates funds to the pool to increase the share price
        // when suer tries to deposit - he gets less due to integer rounding
        // we need to verify that attack is not profitable due to the virtual offset

        // setup
        address attacker = address(0x123);
        address user = address(0x456);
        uint256 initialDepositAmountInTokens = 5;
        uint256 donationAmountInTokens = 1_000_000_000 * 1e6;
        uint256 userDepositAmountInTokens = 1_000_000 * 1e6;

        deal(Currency.unwrap(token0), attacker, initialDepositAmountInTokens + donationAmountInTokens, false);
        deal(Currency.unwrap(token1), attacker, initialDepositAmountInTokens + donationAmountInTokens, false);
        deal(Currency.unwrap(token0), user, userDepositAmountInTokens, false);
        deal(Currency.unwrap(token1), user, userDepositAmountInTokens, false);

        (uint256 attackerShares,, int128 attackerDepositSize0, int128 attackerDepositSize1) =
            depositTokensToHook(initialDepositAmountInTokens, initialDepositAmountInTokens, attacker);
        // verify attacker got shares
        uint256 attackerAssetsBeforeDonation = hook.previewRedeem(attackerShares);

        // donate to the pool
        vm.startPrank(attacker);
        IERC20(Currency.unwrap(token0)).transfer(address(hook), donationAmountInTokens);
        IERC20(Currency.unwrap(token1)).transfer(address(hook), donationAmountInTokens);
        vm.stopPrank();

        uint256 attackerAssetsAfterDonation = hook.previewRedeem(attackerShares);
        (uint256 attackerToken0AfterDonation, uint256 attackerToken1AfterDonation) =
            getTokenAmountsForLiquidity(attackerAssetsAfterDonation);
        assertGt(
            uint256(int256(attackerDepositSize0)) + donationAmountInTokens,
            attackerToken0AfterDonation,
            "Attacker should have less than deposit + donation"
        );
        assertGt(
            uint256(int256(attackerDepositSize0)) + donationAmountInTokens,
            attackerToken1AfterDonation,
            "Attacker should have less than deposit + donation"
        );

        // todo: complete below

        // verify that pool has more tokens
        // verify that share price has increased
        // verify that attacker totalAssets are less than the deposit + donation

        // user deposits
        vm.startPrank(user);
        IERC20(Currency.unwrap(token0)).approve(address(hook), userDepositAmountInTokens);
        IERC20(Currency.unwrap(token1)).approve(address(hook), userDepositAmountInTokens);
        hook.deposit(userDepositAmountInTokens, user, ZERO_BYTES);
        vm.stopPrank();
        // verify that user got shares but less than he should have
    }
}
