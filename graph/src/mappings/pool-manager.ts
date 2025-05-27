import { log } from "@graphprotocol/graph-ts";
import { Swap as SwapEvent } from "../../generated/PoolManager/PoolManager";

import { getPool, trackSwap } from "../entities/pool";
import { createSwap } from "../entities/swap";
import { updateSnapshots, ZERO_BD } from "../helpers";
import { getOrCreateToken } from "../entities/token";

export function handleSwap(event: SwapEvent): void {
  const id = event.params.id;
  const poolId = id.toHexString();

  const pool = getPool(poolId);
  if (pool === null) {
    log.log(log.Level.WARNING, `Swap - Pool not found: ${poolId}`);
    updateSnapshots(event.block);
    return;
  }
  // create swap entity
  const token0 = getOrCreateToken(pool.token0, ZERO_BD);
  const token1 = getOrCreateToken(pool.token1, ZERO_BD);
  createSwap(event, token0, token1);
  trackSwap(pool, event, token0, token1);

  log.log(log.Level.INFO, `Swap processed for pool: ${poolId}`);
}
