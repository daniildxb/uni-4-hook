import { BigInt } from "@graphprotocol/graph-ts";
import {
  Initialize as InitializeEvent,
  Swap as SwapEvent,
} from "../../generated/PoolManager/PoolManager";
import {
  Protocol,
  Pool,
  Swap,
} from "../../generated/schema";
import {
  loadToken,
  createProtocol,
  ZERO_BI,
} from "../helpers";

export function handleInitialize(event: InitializeEvent): void {
  // Load or create protocol
  let protocol = Protocol.load("uniswap-v4-lending-hook");
  if (protocol === null) {
    protocol = createProtocol();
  }

  // Extract pool details from the event
  let poolId = event.params.id.toHexString();

  // Check if pool already exists
  let pool = Pool.load(poolId);
  if (pool !== null) {
    return;
  }

  // Determine token addresses from the event data
  // Note: In a real implementation, you might need to decode the pool ID to get token addresses
  // This is a simplified placeholder approach

  // emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks, sqrtPriceX96, tick);

  // event Initialize PoolId indexed id, Currency indexed currency0, Currency indexed currency1, uint24 fee, int24 tickSpacing, IHooks hooks, uint160 sqrtPriceX96, int24 tick
  let token0Address = event.params.currency0;
  let token1Address = event.params.currency1;
  let hookAddress = event.params.hooks;
  let fee = event.params.fee;
  let tickSpacing = event.params.tickSpacing;
  let currentPrice = event.params.sqrtPriceX96;

  // Load tokens
  let token0 = loadToken(token0Address);
  let token1 = loadToken(token1Address);

  // Create pool entity
  pool = new Pool(poolId);
  pool.protocol = protocol.id;
  pool.hook = hookAddress;
  pool.token0 = token0.id;
  pool.token1 = token1.id;
  pool.tickSpacing = BigInt.fromI32(tickSpacing);
  pool.fee = BigInt.fromI32(fee);
  pool.currentPrice = currentPrice;
  pool.totalValueLockedUSD = ZERO_BI;
  pool.cumulativeSwapFeeUSD = ZERO_BI;
  pool.cumulativeLendingYieldUSD = ZERO_BI;
  pool.createdAtTimestamp = event.block.timestamp;
  pool.createdAtBlockNumber = event.block.number;
  pool.updatedAtTimestamp = event.block.timestamp;
  pool.updatedAtBlockNumber = event.block.number;
  pool.save();
}

export function handleSwap(event: SwapEvent): void {
  /*
        event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );
    */

  // update pool
  // currentPrice, token0AmountPerShare, token1AmountPerShare, cumulativeSwapFeeUSD

  let poolId = event.params.id.toHexString();
  let pool = Pool.load(poolId);
if (pool === null) {
    // Pool not found, return
    return;
}
  pool.currentPrice = event.params.sqrtPriceX96;
  pool.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD.plus(BigInt.fromI32(event.params.fee));

  // create swap entity
  let swap = new Swap(event.transaction.hash.toHexString());
  swap.pool = event.params.id.toHexString();
  swap.sender = event.params.sender;
  swap.amount0 = event.params.amount0;
  swap.amount1 = event.params.amount1;
  swap.fee = BigInt.fromI32(event.params.fee);
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;

  swap.save();
}
