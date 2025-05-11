#!/bin/bash

# Check if ARBITRUM_RPC_URL is set
if [ -z "$ARBITRUM_RPC_URL" ]; then
    echo "Error: ARBITRUM_RPC_URL environment variable is not set"
    echo "Please set it by running: export ARBITRUM_RPC_URL=your_rpc_url"
    exit 1
fi

echo "Starting scheduled swap script execution every 5 minutes"
echo "Press Ctrl+C to stop"

while true; do
    # Generate random amount between 100000 and 30000000
    # Generate random amount between 100000 and 30000000
    # Using $RANDOM which is built into bash (0-32767) to create a more compatible solution
    MIN=100000
    MAX=36000000
    RANGE=$((MAX-MIN+1))
    
    # Generate a random number within our range
    # We use multiple $RANDOM calls to get better distribution for larger numbers
    AMOUNT=$(( MIN + ($RANDOM * 32768 + $RANDOM) % RANGE ))
    
    echo "$(date): Running swap with AMOUNT=$AMOUNT"
    
    # Export the AMOUNT variable for the forge script to use
    export AMOUNT
    
    # Run the forge script
    forge script script/SwapThroughPool.s.sol --rpc-url=$ARBITRUM_RPC_URL --broadcast -v
    
    # Wait for 2 minutes before the next execution
    echo "Waiting 5 minutes until next execution..."
    sleep 300 # 5 minutes
done