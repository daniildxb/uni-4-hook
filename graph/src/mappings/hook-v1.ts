import { log } from "@graphprotocol/graph-ts";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";
import {
  Pool,
} from "../../generated/schema";
import { POOL_ID } from "../helpers/constants";
import {
  trackHookDeposit,
  trackHookWithdraw,
} from "../entities/pool";
import {
  createPosition,
  getPosition,
  trackDeposit,
  trackWithdraw,
} from "../entities/position";
import { createDeposit } from "../entities/deposit";
import { getOrCreateAccount } from "../entities/account";
import { createWithdraw } from "../entities/withdraw";
import { getOrCreateToken } from "../entities/token";

export function handleDeposit(event: DepositEvent): void {
  let poolId = POOL_ID;
  let pool = Pool.load(poolId);

  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found: ${poolId}`);
    return;
  }

  // Load or create user
  let accountAddress = event.params.owner.toHexString();
  getOrCreateAccount(accountAddress);

  // Create position ID
  let position = getPosition(accountAddress, poolId);
  if (position === null) {
    // Create a new position if it doesn't exist
    position = createPosition(accountAddress, poolId, event);
  } else {
    trackDeposit(position, event);
  }

  let token0 = getOrCreateToken(pool.token0);
  let token1 = getOrCreateToken(pool.token1);
  // add deposit entity
  createDeposit(accountAddress, poolId, event, token0, token1);

  // update pool and protocol
  trackHookDeposit(pool, event, token0, token1);
}

export function handleWithdraw(event: WithdrawEvent): void {
  let poolId = POOL_ID;
  let pool = Pool.load(poolId);
  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found: ${poolId}`);
    return;
  }

  // Load or create user
  let address = event.params.owner.toHexString();

  // Create position ID
  let position = getPosition(address, poolId);
  if (position === null) {
    // This should not happen as pool should be created during initialization
    return;
  }
  // Update position
  trackWithdraw(position, event);

  let token0 = getOrCreateToken(pool.token0);
  let token1 = getOrCreateToken(pool.token1);
  // add withdraw entity
  createWithdraw(address, poolId, event, token0, token1);
  trackHookWithdraw(pool, event, token0, token1);
}
