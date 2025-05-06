import { log } from "@graphprotocol/graph-ts";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
  MoneyMarkeyWithdrawal as MoneyMarketWithdrawEvent,
} from "../../generated/HookV1/HookV1";
import {
  Pool,
} from "../../generated/schema";
import { POOL_ID } from "../helpers/constants";
import {
  getDefaultPool,
  trackHookDeposit,
  trackHookWithdraw,
  trackMoneyMarketWithdraw,
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
  position.save();

  // add deposit entity
  createDeposit(accountAddress, poolId, event);

  // update pool and protocol
  trackHookDeposit(pool, event);
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
  position.save();

  // add withdraw entity
  createWithdraw(address, poolId, event);
  trackHookWithdraw(pool, event);
}

  // this happens ** BEFORE ** the swap processing
  // we need to track the amount withdrawn from the money market
  // and compute yield given previous TVL value
export function handleMoneyMarketWithdraw(
  event: MoneyMarketWithdrawEvent
): void {
  const pool = getDefaultPool();
  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found`);
    // This should not happen as pool should be created during initialization
    return;
  }
  trackMoneyMarketWithdraw(pool, event);
}
