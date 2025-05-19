// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract SqrtPriceCalculator {
    /**
     * @notice Calculates the sqrtPriceX96 value for a stablecoin pair considering token decimals
     * @dev Adjusts the price to account for decimal differences, ensuring balanced liquidity
     * @param token0Decimals Decimals used by token0
     * @param token1Decimals Decimals used by token1
     * @return The calculated sqrtPriceX96 value
     */
    function calculateSqrtPriceX96(uint8 token0Decimals, uint8 token1Decimals) public pure returns (uint160) {
        // For stablecoins with identical decimals, price should be 1:1
        if (token0Decimals == token1Decimals) {
            return uint160(1 << 96); // 2^96
        }
        
        // Calculate the decimal difference to adjust the price
        int24 exponent = int24(int8(token1Decimals)) - int24(int8(token0Decimals));
        
        if (exponent > 0) {
            // token1 has more decimals than token0
            // This means token0 is "more valuable" per unit in the pool's accounting
            // We need to decrease the price to balance the liquidity ratio
            uint256 decimalAdjustment = 10 ** uint24(exponent / 2);
            return uint160((1 << 96) / decimalAdjustment);
        } else {
            // token0 has more decimals than token1
            // This means token0 is "less valuable" per unit in the pool's accounting
            // We need to increase the price to balance the liquidity ratio
            uint256 decimalAdjustment = 10 ** uint24(-exponent / 2);
            return uint160((1 << 96) * decimalAdjustment);
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
     * @notice A more precise version that handles extreme decimal differences
     * @dev Use this for tokens with very large decimal differences (>38 decimals)
     * @param token0Decimals Decimals used by token0
     * @param token1Decimals Decimals used by token1
     * @return The calculated sqrtPriceX96 value with protection against overflow
     */
    function calculateSqrtPriceX96Precise(uint8 token0Decimals, uint8 token1Decimals) public pure returns (uint160) {
        // For normal decimal differences, use the standard function
        if (token0Decimals == token1Decimals || 
            (token0Decimals > token1Decimals ? token0Decimals - token1Decimals : token1Decimals - token0Decimals) <= 38) {
            return calculateSqrtPriceX96(token0Decimals, token1Decimals);
        }

        // For extreme cases with very large decimal differences
        int24 exponent = int24(int8(token1Decimals)) - int24(int8(token0Decimals));
        uint256 decimalDifference = exponent > 0 ? uint24(exponent) : uint24(-exponent);
        
        // Split calculation into parts to avoid overflow
        uint256 part1 = 10 ** 19;
        uint256 part2 = 10 ** (decimalDifference / 2 - 19);
        uint256 adjustment = sqrt(part1) * sqrt(part2);
        
        if (exponent > 0) {
            // token1 has more decimals
            return uint160((1 << 96) / adjustment);
        } else {
            // token0 has more decimals
            // Handle potential overflow
            if (adjustment <= type(uint160).max / (1 << 96)) {
                return uint160(adjustment * (1 << 96));
            } else {
                // Scale down if needed
                uint256 scaling = adjustment / ((type(uint160).max / (1 << 96)) + 1) + 1;
                return uint160((adjustment / scaling) * (1 << 96));
            }
        }
    }
}