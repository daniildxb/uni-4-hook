// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SqrtPriceCalculator} from "../../../script/base/PriceCalculator.sol";

/**
 * @title DecimalAdjustedPriceTest
 * @notice Tests to validate the approach to handling stablecoin pools with different token decimals
 */
contract DecimalAdjustedPriceTest is Test, SqrtPriceCalculator {
    // Test case structure
    struct TestCase {
        uint8 decimals0;
        uint8 decimals1;
        int24 expectedTickApprox; // expected tick approximate range
    }

    /**
     * @notice Test the price adjustment approach for stablecoins with different decimals
     * This focuses just on the price calculation, not full pool interactions
     */
    function test_priceCalculation() public {
        // Test data
        TestCase[] memory cases = new TestCase[](3);

        // Case 1: Same decimals (e.g., USDC/USDT both 6 decimals)
        cases[0] = TestCase({
            decimals0: 6,
            decimals1: 6,
            expectedTickApprox: 0 // Price is 1.0, tick is 0
        });

        // Case 2: USDC (6 decimals) / DAI (18 decimals)
        cases[1] = TestCase({
            decimals0: 6,
            decimals1: 18,
            expectedTickApprox: -276325 // Based on our calculation for 6-18 decimals
        });

        // Case 3: DAI (18 decimals) / USDC (6 decimals)
        cases[2] = TestCase({
            decimals0: 18,
            decimals1: 6,
            expectedTickApprox: 276325 // Opposite of case 2
        });

        for (uint256 i = 0; i < cases.length; i++) {
            TestCase memory tc = cases[i];

            // Calculate the price
            uint160 price = calculateSqrtPriceX96(tc.decimals0, tc.decimals1);

            // Convert to tick
            int24 tick = TickMath.getTickAtSqrtPrice(price);

            // Log the results
            emit log_named_uint("Case", i + 1);
            emit log_named_uint("Token0 decimals", tc.decimals0);
            emit log_named_uint("Token1 decimals", tc.decimals1);
            emit log_named_uint("Price (sqrtPriceX96)", price);
            emit log_named_int("Tick", tick);

            // For same decimals, tick should be close to 0
            if (tc.decimals0 == tc.decimals1) {
                assertEq(tick, 0, "Tick should be 0 for same decimals");
            } else {
                // For different decimals, just check that the tick has the right sign and magnitude
                assertApproxEqAbs(tick, tc.expectedTickApprox, 10, "Tick should match expected value");
            }
        }
    }
}
