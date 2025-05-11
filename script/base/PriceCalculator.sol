// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract SqrtPriceCalculator {
    /**
     * @notice Calculates the sqrtPriceX96 value for a stablecoin pair considering token decimals
     * @dev Uses the formula: sqrtPriceX96 = sqrt(amountA / amountB) * 2^96
     * @param tokenADecimals Decimals used by token A
     * @param tokenBDecimals Decimals used by token B
     * @return The calculated sqrtPriceX96 value
     */
    function calculateSqrtPriceX96(uint8 tokenADecimals, uint8 tokenBDecimals) public pure returns (uint160) {
        // If both tokens have the same decimal places and same value, sqrtPrice is just 2^96
        if (tokenADecimals == tokenBDecimals) {
            return uint160(1 << 96); // 2^96
        }

        // Calculate the decimal adjustment between the two tokens
        uint256 decimalAdjustment;
        if (tokenADecimals > tokenBDecimals) {
            decimalAdjustment = 10 ** (tokenADecimals - tokenBDecimals);
            // Square root of the adjustment (since we need sqrt(A/B))
            return uint160(sqrt(decimalAdjustment) * (1 << 96));
        } else {
            decimalAdjustment = 10 ** (tokenBDecimals - tokenADecimals);
            // When B has more decimals, the fraction becomes less than 1
            return uint160((1 << 96) / sqrt(decimalAdjustment));
        }
    }

    /**
     * @notice Calculates the square root of a number using the Babylonian method
     * @dev This is an efficient implementation for sqrt calculation
     * @param x The input number
     * @return y The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        // Initial estimate
        uint256 z = (x + 1) / 2;
        y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * @notice A more precise version that calculates the sqrtPriceX96 for tokens with potentially very different decimal places
     * @dev Handles large decimal differences more carefully to prevent overflows
     * @param tokenADecimals Decimals used by token A
     * @param tokenBDecimals Decimals used by token B
     * @return The calculated sqrtPriceX96 value with higher precision
     */
    function calculateSqrtPriceX96Precise(uint8 tokenADecimals, uint8 tokenBDecimals) public pure returns (uint160) {
        if (tokenADecimals == tokenBDecimals) {
            return uint160(1 << 96); // 2^96
        }

        // We'll handle the calculation in parts to avoid overflows
        uint256 decimalDifference;
        bool aHasMoreDecimals = tokenADecimals > tokenBDecimals;

        if (aHasMoreDecimals) {
            decimalDifference = tokenADecimals - tokenBDecimals;
        } else {
            decimalDifference = tokenBDecimals - tokenADecimals;
        }

        // For very large differences, we need to handle the calculation carefully
        if (decimalDifference > 38) {
            // Arbitrary threshold where we need more care
            // Split the decimal power into parts
            uint256 part1 = 10 ** 19;
            uint256 part2 = 10 ** (decimalDifference - 19);

            uint256 sqrtPart1 = sqrt(part1);
            uint256 sqrtPart2 = sqrt(part2);

            uint256 result;
            if (aHasMoreDecimals) {
                // Be careful with potential overflow
                result = sqrtPart1 * sqrtPart2;
                // Apply 2^96 factor carefully
                if (result <= type(uint160).max / (1 << 96)) {
                    return uint160(result * (1 << 96));
                } else {
                    // Handle large values by scaling down
                    uint256 scaling = result / ((type(uint160).max / (1 << 96)) + 1) + 1;
                    return uint160((result / scaling) * (1 << 96));
                }
            } else {
                // When B has more decimals
                return uint160((1 << 96) / (sqrtPart1 * sqrtPart2));
            }
        } else {
            // For smaller differences, the original approach works
            uint256 decimalAdjustment = 10 ** decimalDifference;

            if (aHasMoreDecimals) {
                return uint160(sqrt(decimalAdjustment) * (1 << 96));
            } else {
                return uint160((1 << 96) / sqrt(decimalAdjustment));
            }
        }
    }
}
