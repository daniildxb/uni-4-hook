import {
  Initialize as InitializeEvent,
  Swap as SwapEvent,
} from "../../generated/PoolManager/PoolManager";
import { log, BigInt, BigDecimal, ethereum } from "@graphprotocol/graph-ts";
import { Pool, PoolHourlySnapshots, Protocol } from "../../generated/schema";
import { POOL_ID, SECONDS_IN_HOUR } from "../helpers/constants";
import { ZERO_BD, ZERO_BI } from "../helpers";
import { convertTokenToUSD, getOrCreateToken } from "./token";
import { bumpFeesAndTVL, getOrCreateProtocol } from "./protocol";
import {
  MoneyMarkeyWithdrawal as MoneyMarketWithdrawEvent,
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";

export function getDefaultPool(): Pool | null {
  let pool = Pool.load(POOL_ID);
  if (pool === null) {
    log.log(log.Level.WARNING, `[POOL] Pool not found: ${POOL_ID}`);
    return null;
  }
  return pool;
}

export function getPool(poolId: string): Pool | null {
  return Pool.load(poolId);
}

export function createPool(event: InitializeEvent): Pool {
  // Determine token addresses from the event data
  let token0Address = event.params.currency0;
  let token1Address = event.params.currency1;
  let hookAddress = event.params.hooks;
  let fee = event.params.fee;
  let tickSpacing = event.params.tickSpacing;
  let currentPrice = event.params.sqrtPriceX96;
  let poolId = event.params.id.toHexString();

  // Load tokens
  log.log(log.Level.INFO, `Loading tokens`);
  let token0 = getOrCreateToken(token0Address.toHexString());
  let token1 = getOrCreateToken(token1Address.toHexString());

  // Create pool entity
  let pool = new Pool(poolId);
  pool.protocol = getOrCreateProtocol().id;
  pool.hook = hookAddress;
  pool.token0 = token0.id;
  pool.token1 = token1.id;
  pool.tickSpacing = BigInt.fromI32(tickSpacing);
  pool.fee = BigInt.fromI32(fee);
  pool.currentPrice = currentPrice;
  pool.token0AmountPerShare = ZERO_BD;
  pool.token1AmountPerShare = ZERO_BD;
  pool.totalValueLockedUSD = ZERO_BD;
  pool.cumulativeSwapFeeUSD = ZERO_BD;
  pool.cumulativeLendingYieldUSD = ZERO_BD;
  pool.createdAtTimestamp = event.block.timestamp;
  pool.createdAtBlockNumber = event.block.number;
  pool.updatedAtTimestamp = event.block.timestamp;
  pool.updatedAtBlockNumber = event.block.number;
  pool.save();
  return pool;
}

export function poolIdMatchesExpected(poolId: string): boolean {
  return poolId == POOL_ID;
}

export function trackSwap(pool: Pool, event: SwapEvent): void {
  let feeTokenAddress =
    event.params.amount0 > ZERO_BI ? pool.token1 : pool.token0;
  let feeToken = getOrCreateToken(feeTokenAddress);
  let feeUSD = convertTokenToUSD(feeToken, BigInt.fromI32(event.params.fee));

  pool.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD.plus(feeUSD);
  pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(feeUSD);

  pool.currentPrice = event.params.sqrtPriceX96;
  _updateTimestamps(pool, event.block);
  bumpFeesAndTVL(feeUSD);

  pool.save();
}

// export function track

export function trackHookDeposit(pool: Pool, event: DepositEvent): Pool {
  let token0 = getOrCreateToken(pool.token0);
  let token1 = getOrCreateToken(pool.token1);

  let token0DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token0.decimals))
  );
  let token1DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token1.decimals))
  );

  let depositUSD = event.params.assets0.toBigDecimal().div(token0DecimalsBD);
  depositUSD = depositUSD.plus(
    event.params.assets1.toBigDecimal().div(token1DecimalsBD)
  );

  pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(depositUSD);

  _updateTimestamps(pool, event.block);
  pool.save();

  let protocol = getOrCreateProtocol();
  protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(depositUSD);
  protocol.save();
  return pool;
}

export function trackHookWithdraw(pool: Pool, event: WithdrawEvent): Pool {
  let token0 = getOrCreateToken(pool.token0);
  let token1 = getOrCreateToken(pool.token1);

  let token0DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token0.decimals))
  );
  let token1DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token1.decimals))
  );

  let withdrawUSD = event.params.assets0.toBigDecimal().div(token0DecimalsBD);
  withdrawUSD = withdrawUSD.plus(
    event.params.assets1.toBigDecimal().div(token1DecimalsBD)
  );

  pool.totalValueLockedUSD = pool.totalValueLockedUSD.minus(withdrawUSD);

  _updateTimestamps(pool, event.block);
  pool.save();

  let protocol = getOrCreateProtocol();
  protocol.totalValueLockedUSD =
    protocol.totalValueLockedUSD.minus(withdrawUSD);
  protocol.save();
  return pool;
}

export function trackMoneyMarketWithdraw(
  pool: Pool,
  event: MoneyMarketWithdrawEvent
): Pool {
  let oldTVL = pool.totalValueLockedUSD;

  let token0 = getOrCreateToken(pool.token0);
  let token1 = getOrCreateToken(pool.token1);

  let token0UsdAmount = convertTokenToUSD(token0, event.params.amount0);
  let token1UsdAmount = convertTokenToUSD(token1, event.params.amount1);

  let newTVL = token0UsdAmount.plus(token1UsdAmount);
  let yieldUSD = newTVL.minus(oldTVL);
  pool.totalValueLockedUSD = newTVL;
  pool.cumulativeLendingYieldUSD =
    pool.cumulativeLendingYieldUSD.plus(yieldUSD);
  _updateTimestamps(pool, event.block);
  bumpFeesAndTVL(yieldUSD);
  pool.save();
  return pool;
}

export function getOrCreateSnapshot(
  pool: Pool,
  block: ethereum.Block
): PoolHourlySnapshots {
  let id: string = (block.timestamp.toI64() / SECONDS_IN_HOUR).toString();
  let snapshot = PoolHourlySnapshots.load(id);
  if (snapshot) {
    return snapshot;
  }

  snapshot = new PoolHourlySnapshots(id);
  snapshot.pool = pool.id;
  snapshot.totalValueLockedUSD = pool.totalValueLockedUSD;
  snapshot.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD;
  snapshot.cumulativeLendingYieldUSD = pool.cumulativeLendingYieldUSD;
  snapshot.save();
  return snapshot;
}

function _updateTimestamps(pool: Pool, block: ethereum.Block): void {
  pool.updatedAtTimestamp = block.timestamp;
  pool.updatedAtBlockNumber = block.number;
}
