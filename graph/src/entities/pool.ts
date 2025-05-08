import {
  Initialize as InitializeEvent,
  Swap as SwapEvent,
} from "../../generated/PoolManager/PoolManager";
import {
  log,
  BigInt,
  BigDecimal,
  ethereum,
  Address,
} from "@graphprotocol/graph-ts";
import { Pool, PoolHourlySnapshots, Protocol } from "../../generated/schema";
import { POOL_ID, SECONDS_IN_HOUR } from "../helpers/constants";
import { ZERO_BD, ZERO_BI } from "../helpers";
import { convertTokenToUSD, getOrCreateToken } from "./token";
import { bumpProtocolStats, getOrCreateProtocol } from "./protocol";
import {
  MoneyMarkeyWithdrawal as MoneyMarketWithdrawEvent,
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
  HookV1,
} from "../../generated/HookV1/HookV1";
import { sqrtPriceX96ToTokenPrices } from "../sqrtMath";
import { ERC20 } from "../../generated/HookV1/ERC20";

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
  const hookContract = HookV1.bind(hookAddress);
  let fee = event.params.fee;
  let tickSpacing = event.params.tickSpacing;
  let poolId = event.params.id.toHexString();

  // Load tokens
  log.log(log.Level.INFO, `Loading tokens`);
  let token0 = getOrCreateToken(token0Address.toHexString());
  let token1 = getOrCreateToken(token1Address.toHexString());

  const prices = sqrtPriceX96ToTokenPrices(
    event.params.sqrtPriceX96,
    token0,
    token1
  );

  // Create pool entity
  let pool = new Pool(poolId);
  pool.protocol = getOrCreateProtocol().id;
  pool.hook = hookAddress;
  pool.token0 = token0.id;
  pool.token1 = token1.id;
  pool.aToken0 = hookContract.aToken0().toHexString();
  pool.aToken1 = hookContract.aToken1().toHexString();
  pool.tickSpacing = BigInt.fromI32(tickSpacing);
  pool.fee = BigInt.fromI32(fee);
  pool.currentPrice = prices[0];
  pool.totalValueLockedUSD = ZERO_BD;
  pool.cumulativeSwapFeeUSD = ZERO_BD;
  pool.cumulativeLendingYieldUSD = ZERO_BD;
  pool.cumulativeVolumeUSD = ZERO_BD;
  pool.shares = ZERO_BI;
  pool.token0Amount = ZERO_BI;
  pool.token1Amount = ZERO_BI;
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
  const token0 = getOrCreateToken(pool.token0);
  const token1 = getOrCreateToken(pool.token1);
  let feeToken = event.params.amount0 > ZERO_BI ? token1 : token0;
  let feeUSD = convertTokenToUSD(feeToken, BigInt.fromI32(event.params.fee));

  pool.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD.plus(feeUSD);
  pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(feeUSD);
  // input token will be negative and output token will be positive
  // hence we subtract instead of adding
  pool.token0Amount = pool.token0Amount.minus(event.params.amount0);
  pool.token1Amount = pool.token1Amount.minus(event.params.amount1);
  // input token amount is negative, hence we negate
  const swapVolumeUSD =
    event.params.amount0 > ZERO_BI
      ? convertTokenToUSD(token1, event.params.amount1).neg()
      : convertTokenToUSD(token0, event.params.amount0).neg();
  pool.cumulativeVolumeUSD = pool.cumulativeVolumeUSD.plus(swapVolumeUSD);

  const prices = sqrtPriceX96ToTokenPrices(
    event.params.sqrtPriceX96,
    token0,
    token1
  );
  pool.currentPrice = prices[0];

  _updateTimestamps(pool, event.block);
  bumpProtocolStats(feeUSD, swapVolumeUSD);

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
  pool.shares = pool.shares.plus(event.params.shares);
  pool.token0Amount = pool.token0Amount.plus(event.params.assets0);
  pool.token1Amount = pool.token1Amount.plus(event.params.assets1);

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
  pool.shares = pool.shares.minus(event.params.shares);

  pool.totalValueLockedUSD = pool.totalValueLockedUSD.minus(withdrawUSD);
  pool.token0Amount = pool.token0Amount.minus(event.params.assets0);
  pool.token1Amount = pool.token1Amount.minus(event.params.assets1);

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

  pool.token0Amount = event.params.amount0;
  pool.token1Amount = event.params.amount1;

  _updateTimestamps(pool, event.block);
  bumpProtocolStats(yieldUSD, ZERO_BD);
  pool.save();
  return pool;
}

export function calculateAPY(
  rateIncreaseUSD: BigDecimal,
  initialValueUSD: BigDecimal,
  timeDeltaSeconds: number
): BigDecimal {
  if (initialValueUSD.le(BigDecimal.zero()) || timeDeltaSeconds <= 0) {
    log.error(
      "Invalid input: initial value or time delta is zero or negative",
      []
    );
    return BigDecimal.zero();
  }

  const finalValue = initialValueUSD.plus(rateIncreaseUSD);
  const growthFactor = finalValue.div(initialValueUSD);

  // Convert to f64 to do exponentiation
  const base = parseFloat(growthFactor.toString());
  const SECONDS_PER_YEAR = 365 * 24 * 60 * 60;
  const exponent = SECONDS_PER_YEAR / timeDeltaSeconds; // safe since it's time

  const apyValue = Math.pow(base, exponent) - 1;

  return BigDecimal.fromString(apyValue.toString());
}

export function getOrCreateSnapshot(
  pool: Pool,
  block: ethereum.Block
): PoolHourlySnapshots {
  let idNum = block.timestamp.toI64() / SECONDS_IN_HOUR;
  let id: string = idNum.toString();
  let snapshot = PoolHourlySnapshots.load(id);
  if (snapshot) {
    // shouldn't happen, but just in case
    return snapshot;
  }

  const previousSnapshot = PoolHourlySnapshots.load((idNum - 1).toString());
  let rate = ZERO_BD;
  if (previousSnapshot) {
    const usdYield = pool.cumulativeLendingYieldUSD
      .plus(pool.cumulativeSwapFeeUSD)
      .minus(previousSnapshot.cumulativeLendingYieldUSD)
      .minus(previousSnapshot.cumulativeSwapFeeUSD);
    const timeDelta = SECONDS_IN_HOUR;
    rate = calculateAPY(
      usdYield,
      previousSnapshot.totalValueLockedUSD,
      timeDelta
    );
  }

  snapshot = new PoolHourlySnapshots(id);
  snapshot.pool = pool.id;
  snapshot.currentPrice = pool.currentPrice;
  snapshot.totalValueLockedUSD = pool.totalValueLockedUSD;
  snapshot.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD;
  snapshot.cumulativeLendingYieldUSD = pool.cumulativeLendingYieldUSD;
  snapshot.cumulativeVolumeUSD = pool.cumulativeVolumeUSD;
  snapshot.rate = rate;
  snapshot.shares = pool.shares;
  snapshot.save();
  return snapshot;
}

// called once an hour by the snapshot updator
export function updatePoolLendingYield(
  pool: Pool,
  block: ethereum.Block
): BigDecimal {
  // fetch atoken balance of the hook
  let aToken0Contract = ERC20.bind(Address.fromString(pool.aToken0));
  let aToken1Contract = ERC20.bind(Address.fromString(pool.aToken1));

  let aToken0Balance = aToken0Contract.balanceOf(Address.fromBytes(pool.hook));
  let aToken1Balance = aToken1Contract.balanceOf(Address.fromBytes(pool.hook));

  let token0Yield = aToken0Balance.minus(pool.token0Amount);
  let token1Yield = aToken1Balance.minus(pool.token1Amount);

  pool.token0Amount = aToken0Balance;
  pool.token1Amount = aToken1Balance;

  const yieldUSD = convertTokenToUSD(
    getOrCreateToken(pool.token0),
    token0Yield
  ).plus(convertTokenToUSD(getOrCreateToken(pool.token1), token1Yield));
  pool.cumulativeLendingYieldUSD =
    pool.cumulativeLendingYieldUSD.plus(yieldUSD);
  pool.totalValueLockedUSD = yieldUSD.plus(pool.totalValueLockedUSD);

  _updateTimestamps(pool, block);

  pool.save();
  return yieldUSD;
}

function _updateTimestamps(pool: Pool, block: ethereum.Block): void {
  pool.updatedAtTimestamp = block.timestamp;
  pool.updatedAtBlockNumber = block.number;
}
