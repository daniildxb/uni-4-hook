import { log } from "@graphprotocol/graph-ts";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
  FeesTracked as FeesTrackedEvent,
  FeesCollected as FeesCollectedEvent,
  Transfer as TransferEvent
} from "../../generated/HookV1/HookV1";
import {
  getPoolFromHookAddress,
  trackFeesCollected,
  trackHookDeposit,
  trackHookWithdraw,
  trackProtocolFee,
} from "../entities/pool";
import {
  createPosition,
  getPosition,
  trackDeposit,
  trackTransfer,
  trackWithdraw,
} from "../entities/position";
import { createDeposit } from "../entities/deposit";
import { createAccount, getAccount } from "../entities/account";
import { createWithdraw } from "../entities/withdraw";
import { getOrCreateToken } from "../entities/token";
import { createTransfer } from "../entities/transfer";
import { ZERO_BD } from "../helpers";

export function handleDeposit(event: DepositEvent): void {
  const pool = getPoolFromHookAddress(event.address);

  if (pool === null) {
    log.warning('[HOOK] Pool not found for hook: {}', [event.address.toString()]);
    return;
  }

  // Load or create user
  let accountAddress = event.params.owner.toHexString();
  // todo: change so that when if account is only created now - we'd track ref code
  const account = getAccount(accountAddress);
  if (account === null) {
    // Create a new account if it doesn't exist
    createAccount(accountAddress, event.params.referral);
  }
  // Create position ID
  let position = getPosition(accountAddress, pool.id);
  if (position === null) {
    // Create a new position if it doesn't exist
    log.warning('[HOOK] DEPOSIT Creating position: {} and pool: {}', [accountAddress, pool.id]);
    position = createPosition(accountAddress, pool.id, event.params.shares, event);
  } else {
    log.warning('[HOOK] DEPOSIT Position found: {} and pool: {}', [accountAddress, pool.id]);
    trackDeposit(position, event);
  }

  let token0 = getOrCreateToken(pool.token0, ZERO_BD);
  let token1 = getOrCreateToken(pool.token1, ZERO_BD);
  // add deposit entity
  createDeposit(accountAddress, pool.id, event, token0, token1);

  // update pool and protocol
  trackHookDeposit(pool, event, token0, token1);
}

export function handleWithdraw(event: WithdrawEvent): void {
  log.warning('[HOOK] Withdraw event', []);
  const pool = getPoolFromHookAddress(event.address);
  if (pool === null) {
    log.warning('[HOOK] Pool not found for hook: {}', [event.address.toString()]);
    return;
  }

  // Load or create user
  let address = event.params.owner.toHexString();

  // Create position ID
  let position = getPosition(address, pool.id);
  if (position === null) {
    log.warning('[HOOK] Position not found for address: {} and pool: {}', [address, pool.id]);
    // This should not happen as pool should be created during initialization
    return;
  }
  // Update position
  trackWithdraw(position, event);

  let token0 = getOrCreateToken(pool.token0, ZERO_BD);
  let token1 = getOrCreateToken(pool.token1, ZERO_BD);
  // add withdraw entity
  createWithdraw(address, pool.id, event, token0, token1);
  trackHookWithdraw(pool, event, token0, token1);
}

export function handleFeesTracked(event: FeesTrackedEvent): void {
  const pool = getPoolFromHookAddress(event.address);
  if (pool === null) {
    log.warning('[HOOK] Pool not found for hook: {}', [event.address.toString()]);
    return;
  }

  trackProtocolFee(pool, event);
}

export function handleFeesCollected(event: FeesCollectedEvent): void {
  const pool = getPoolFromHookAddress(event.address);

  if (pool === null) {
    log.warning('[HOOK] Pool not found for hook: {}', [event.address.toString()]);
    return;
  }

  trackFeesCollected(pool, event);
}

export function handleTransfer(event: TransferEvent): void {
  // ignore transfers to or from the zero address
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
  if (event.params.from.toHexString() == ZERO_ADDRESS || event.params.to.toHexString() == ZERO_ADDRESS) {
    return;
  }

  if (event.params.from.toHexString() == event.params.to.toHexString()) {
    // Ignore self transfers
    return;
  }
  const pool = getPoolFromHookAddress(event.address);
  if (pool === null) {
    log.warning('[HOOK] Pool not found for hook: {}', [event.address.toString()]);
    return;
  }

  // Load or create user
  const fromAccountAddress = event.params.from.toHexString();

  const toAccountAddress = event.params.to.toHexString();

  createTransfer(pool, event)

  trackTransfer(fromAccountAddress, toAccountAddress, pool, event);
}