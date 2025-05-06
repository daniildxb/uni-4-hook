import { log } from '@graphprotocol/graph-ts';
import {
  Initialize as InitializeEvent,
  Swap as SwapEvent,
} from "../../generated/PoolManager/PoolManager";
import { Protocol } from "../../generated/schema";

import { createPool, getPool, poolIdMatchesExpected, trackSwap } from '../entities/pool';
import { createSwap } from '../entities/swap';
import { getOrCreateProtocol } from '../entities/protocol';

export function handleInitialize(event: InitializeEvent): void {
  // Load or create protocol
  let protocol = getOrCreateProtocol();

  // Extract pool details from the event
  let id = event.params.id;
  let poolId = id.toHexString();


  if (poolIdMatchesExpected(poolId)) {
    log.log(log.Level.INFO, `Pool ID check passed with at least one method`);
    createPool(event);
    log.log(log.Level.INFO, `Pool entity saved`);
  }
}

export function handleSwap(event: SwapEvent): void {
  let id = event.params.id;
  let poolId = id.toHexString();

  if (poolIdMatchesExpected(poolId)) {
    log.log(log.Level.INFO, `Swap - Pool ID check passed`);
    let pool = getPool(poolId);
    if (pool === null) {
      log.log(log.Level.WARNING, `Swap - Pool not found: ${poolId}`);
      return;
    }
    // create swap entity
    createSwap(event);
    trackSwap(pool, event);

    log.log(log.Level.INFO, `Swap processed for pool: ${poolId}`);
  }
}
