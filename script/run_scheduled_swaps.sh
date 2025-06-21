#!/bin/bash

# Check if ARBITRUM_RPC_URL is set
if [ -z "$ARBITRUM_RPC_URL" ]; then
    echo "Error: ARBITRUM_RPC_URL environment variable is not set"
    echo "Please set it by running: export ARBITRUM_RPC_URL=your_rpc_url"
    exit 1
fi

echo "Starting scheduled swap script execution every 15 minutes"
echo "Press Ctrl+C to stop"

while true; do
    # Generate random amount between 1 and 36
    MIN=100000
    MAX=3600000
    RANGE=$((MAX-MIN+1))
    
    # Generate a random number within our range
    # We use multiple $RANDOM calls to get better distribution for larger numbers
    AMOUNT=$(( MIN + ($RANDOM * 32768 + $RANDOM) % RANGE ))
    
    echo "$(date): Running swaps with AMOUNT=$AMOUNT"

    # Export the AMOUNT variable for the forge script to use
    export AMOUNT

    
    # Run the forge script for USDC/USDT pool (POOL_ENUM=0)
    echo "Running swap for GHO/USDC pool (POOL_ENUM=4)"
    POOL_ENUM=4 forge script script/SwapThroughPool.s.sol --rpc-url=$BASE_RPC_URL --broadcast -v
    
    # Run the forge script for USDT/DAI pool (POOL_ENUM=1)
    echo "Running swap for VIRTUAL/USDC pool (POOL_ENUM=5)"
    POOL_ENUM=5 forge script script/SwapThroughPool.s.sol --rpc-url=$BASE_RPC_URL --broadcast -v
    
    # Wait for 5 minutes before the next execution
    echo "Waiting 15 minutes until next execution..."
    sleep 900 # 15 minutes
done