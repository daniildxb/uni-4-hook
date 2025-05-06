import { BigDecimal, BigInt, log } from "@graphprotocol/graph-ts";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";
import {
  Pool,
  Account,
  Position,
  Deposit,
  Withdrawal,
  Protocol,
} from "../../generated/schema";
import { POOL_ID } from "../helpers/constants";
import { loadTokenByAddressString } from "../helpers";

export function handleDeposit(event: DepositEvent): void {
  // Load the pool (must be created during initialize event)
  // let hookAddress = event.address.toHexString();
  // todo: store poolId <> hook mapping somewhere, or emit poolId in the event
  let poolId = POOL_ID;
  let pool = Pool.load(poolId);

  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found: ${poolId}`);
    // This should not happen as pool should be created during initialization
    return;
  }

  let protocol = Protocol.load(pool.protocol);
  if (protocol === null) {
    log.log(log.Level.WARNING, `[HOOK] Protocol not found: ${pool.protocol}`);
    // This should not happen as protocol should be created during initialization
    return;
  }


  // Load or create user
  let address = event.params.owner.toHexString();
  let account = Account.load(address);
  if (account === null) {
    account = new Account(address);
    account.save();
  }

  // Create position ID
  let positionId = `${address}-${poolId}`;
  let position = Position.load(positionId);

  // create deposit entity

  // Create a new position if it doesn't exist
  if (position === null) {
    position = new Position(positionId);
    position.account = address;
    position.pool = poolId;
    position.shares = event.params.shares;
    position.createdAtTimestamp = event.block.timestamp;
    position.createdAtBlockNumber = event.block.number;
    position.updatedAtTimestamp = event.block.timestamp;
    position.updatedAtBlockNumber = event.block.number;
  } else {
    // Update position
    position.shares = position.shares.plus(event.params.shares);
    position.updatedAtTimestamp = event.block.timestamp;
    position.updatedAtBlockNumber = event.block.number;
  }

  position.save();

  // add deposit entity
  let depositId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let deposit = new Deposit(depositId);
  deposit.account = address;
  deposit.pool = poolId;
  deposit.position = positionId;
  deposit.token0Amount = event.params.assets0;
  deposit.token1Amount = event.params.assets1;
  deposit.shares = event.params.shares;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.save();

  let token0 = loadTokenByAddressString(pool.token0);
  let token1 = loadTokenByAddressString(pool.token1);

  let token0DecimalsBD = new BigDecimal(BigInt.fromI32(10).pow(u8(token0.decimals)));
  let token1DecimalsBD = new BigDecimal(BigInt.fromI32(10).pow(u8(token1.decimals)));

  let depositUSD = event.params.assets0.toBigDecimal().div(token0DecimalsBD);
  depositUSD = depositUSD.plus(event.params.assets1.toBigDecimal().div(token1DecimalsBD));

  pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(depositUSD);
  protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(depositUSD);

  pool.save();
  protocol.save();
}

export function handleWithdraw(event: WithdrawEvent): void {
  // Load the pool (must be created during initialize event)
  // let hookAddress = event.address.toHexString();
  // todo: store poolId <> hook mapping somewhere, or emit poolId in the event
  let poolId = `0xeb4b62640827a59dd667017b5e8e14533479be83d1c7145775db1716274d4360`;

  // Load or create user
  let address = event.params.owner.toHexString();

  // Create position ID
  let positionId = `${address}-${poolId}`;
  let position = Position.load(positionId);
  if (position === null) {
    // This should not happen as pool should be created during initialization
    return;
  }

  // create deposit entity

  // Create a new position if it doesn't exist
  // Update position
  position.shares = position.shares.minus(event.params.shares);
  position.updatedAtTimestamp = event.block.timestamp;
  position.updatedAtBlockNumber = event.block.number;
  position.save();

  // add deposit entity
  let withdrawalId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let withdrawal = new Withdrawal(withdrawalId);
  withdrawal.account = address;
  withdrawal.pool = poolId;
  withdrawal.position = positionId;
  withdrawal.token0Amount = event.params.assets0;
  withdrawal.token1Amount = event.params.assets1;
  withdrawal.shares = event.params.shares;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.blockNumber = event.block.number;
  withdrawal.save();

  // // Update token balances
  // todo: update pool token amounts per share
  // todo: update protocol TVL
  // updateTokenBalances(pool, token0Amount, token1Amount, true);

  // // Update TVL for pool and protocol
  // updatePoolTVL(pool, amountUSD, true);
  // updateProtocolTVL(protocol, amountUSD, true);
}

export function handleMoneyMarketDeposit(event: DepositEvent): void {
  // this happens ** AFTER ** the swap processing
  // no need to update things as they are already updated in the swap processing
}

export function handleMoneyMarketWithdraw(event: WithdrawEvent): void {
  // this happens ** BEFORE ** the swap processing
  // we need to track the amount withdrawn from the money market
  // and compute yield given previous TVL value
  let poolId = POOL_ID;
  let pool = Pool.load(poolId);

  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found: ${poolId}`);
    // This should not happen as pool should be created during initialization
    return;
  }

  let protocol = Protocol.load(pool.protocol);
  if (protocol === null) {
    log.log(log.Level.WARNING, `[HOOK] Protocol not found: ${pool.protocol}`);
    // This should not happen as protocol should be created during initialization
    return;
  }

  let oldTVL = pool.totalValueLockedUSD;

  let token0 = loadTokenByAddressString(pool.token0);
  let token1 = loadTokenByAddressString(pool.token1);

  let token0DecimalsBD = new BigDecimal(BigInt.fromI32(10).pow(u8(token0.decimals)));
  let token1DecimalsBD = new BigDecimal(BigInt.fromI32(10).pow(u8(token1.decimals)));

  let token0UsdAmount = event.params.assets0.toBigDecimal().div(token0DecimalsBD);
  let token1UsdAmount = event.params.assets1.toBigDecimal().div(token1DecimalsBD);

  let newTVL = token0UsdAmount.plus(token1UsdAmount);
  let yieldUSD = newTVL.minus(oldTVL);
  pool.totalValueLockedUSD = newTVL;
  pool.cumulativeLendingYieldUSD = pool.cumulativeLendingYieldUSD.plus(yieldUSD);
  protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(yieldUSD);
  protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(yieldUSD);
}
