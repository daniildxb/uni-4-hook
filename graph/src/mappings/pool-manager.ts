import { log, BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  Initialize as InitializeEvent,
  Swap as SwapEvent,
} from "../../generated/PoolManager/PoolManager";
import { Protocol, Pool, Swap } from "../../generated/schema";
import { loadToken, createProtocol, ZERO_BI, ZERO_BD } from "../helpers";

export function handleInitialize(event: InitializeEvent): void {
  // Load or create protocol
  let protocol = Protocol.load("uniswap-v4-lending-hook");
  if (protocol === null) {
    protocol = createProtocol();
  }

  // Extract pool details from the event
  let id = event.params.id;
  let idString = id.toHexString();
  let expectedIdString = "0xeb4b62640827a59dd667017b5e8e14533479be83d1c7145775db1716274d4360";
  
  if (idString == expectedIdString) {
    log.log(log.Level.INFO, `Pool ID check passed with at least one method`);
    
    // Continue with handler logic
    let poolId = idString;
    let pool = Pool.load(poolId);
 
    // Determine token addresses from the event data
    let token0Address = event.params.currency0;
    let token1Address = event.params.currency1;
    let hookAddress = event.params.hooks;
    let fee = event.params.fee;
    let tickSpacing = event.params.tickSpacing;
    let currentPrice = event.params.sqrtPriceX96;

    // Load tokens
    log.log(log.Level.INFO, `Loading tokens`);
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
    pool.token0AmountPerShare = ZERO_BD;
    pool.token1AmountPerShare = ZERO_BD;
    pool.totalValueLockedUSD = ZERO_BI;
    pool.cumulativeSwapFeeUSD = ZERO_BI;
    pool.cumulativeLendingYieldUSD = ZERO_BI;
    pool.createdAtTimestamp = event.block.timestamp;
    pool.createdAtBlockNumber = event.block.number;
    pool.updatedAtTimestamp = event.block.timestamp;
    pool.updatedAtBlockNumber = event.block.number;
    log.log(log.Level.INFO, `Saving pool entity`);
    pool.save();
    log.log(log.Level.INFO, `Pool entity saved`);
  }
}

export function handleSwap(event: SwapEvent): void {
  // Pool ID comparison with multiple checks
  let id = event.params.id;
  let idString = id.toHexString();
  let expectedIdString = "0xeb4b62640827a59dd667017b5e8e14533479be83d1c7145775db1716274d4360";
  
  if (idString === expectedIdString) {
    log.log(log.Level.INFO, `Swap - Pool ID check passed`);
    
    let poolId = idString;
    let pool = Pool.load(poolId);
    
    if (pool === null) {
      log.log(log.Level.WARNING, `Swap - Pool not found: ${poolId}`);
      return;
    }
    
    pool.currentPrice = event.params.sqrtPriceX96;
    pool.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD.plus(
      BigInt.fromI32(event.params.fee)
    );
    pool.updatedAtTimestamp = event.block.timestamp;
    pool.updatedAtBlockNumber = event.block.number;
    pool.save();

    // create swap entity
    let swapId = event.transaction.hash.toHexString().concat('-').concat(event.logIndex.toString());
    let swap = new Swap(swapId);
    swap.pool = poolId;
    swap.sender = event.params.sender;
    swap.amount0 = event.params.amount0;
    swap.amount1 = event.params.amount1;
    swap.fee = BigInt.fromI32(event.params.fee);
    swap.timestamp = event.block.timestamp;
    swap.blockNumber = event.block.number;
    swap.save();
    
    log.log(log.Level.INFO, `Swap processed for pool: ${poolId}`);
  }
}
