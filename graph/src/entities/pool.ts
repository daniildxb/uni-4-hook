import { HookDeployed as HookDeployedEvent } from '../../generated/HookV1/HookManager';
import {
  Initialize as InitializeEvent,
  PoolManager,
  Swap as SwapEvent,
} from "../../generated/PoolManager/PoolManager";
import {
  log,
  BigInt,
  BigDecimal,
  ethereum,
  Address,
} from "@graphprotocol/graph-ts";
import { Pool, PoolHourlySnapshots, Protocol, Token } from "../../generated/schema";
import { SECONDS_IN_HOUR } from "../helpers/constants";
import { ZERO_BD, ZERO_BI } from "../helpers";
import { convertTokenToUSD, getOrCreateToken } from "./token";
import { bumpProtocolStats, getOrCreateProtocol } from "./protocol";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
  FeesTracked as FeesTrackedEvent,
  FeesCollected as FeesCollectedEvent,
  HookV1,
} from "../../generated/HookV1/HookV1";
import { sqrtPriceX96ToTokenPrices } from "../sqrtMath";
import { ERC20 } from "../../generated/HookV1/ERC20";

export function getPool(poolId: string): Pool | null {
  return Pool.load(poolId);
}

export function getPoolFromHookAddress(hookAddress: Address): Pool | null {
  const hookContract = HookV1.bind(hookAddress);
  const poolId = hookContract.getPoolId().toHexString().toLowerCase();
  return getPool(poolId);
}

export function createPoolFromHookManagerEvent(event: HookDeployedEvent): Pool {
  const hookAddress = event.params.hook;
  const poolId = event.params.poolId.toHexString().toLowerCase();

  const hookContract = HookV1.bind(hookAddress);

  let token0 = getOrCreateToken(hookContract.token0().toHexString());
  let token1 = getOrCreateToken(hookContract.token1().toHexString());
  const result = hookContract.key();
  const fee = result.value2;
  const tickSpacing = result.value3;

  const price = event.params.sqrtPriceX96;
  const prices = sqrtPriceX96ToTokenPrices(
    price,
    token0,
    token1
  );

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
  pool.unclaimedProtocolFeeUSD = ZERO_BD;
  pool.claimedProtocolFeeUSD = ZERO_BD;
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

export function poolIdMatchesExpected(poolId: string, protocol: Protocol | null): boolean {
  if (protocol === null) {
    protocol = getOrCreateProtocol();
  }
  const POOL_IDS = protocol.pools.load().map(el => el.id.toLowerCase());
  return POOL_IDS.includes(poolId);
}

export function trackSwap(pool: Pool, event: SwapEvent, _token0: Token, _token1: Token): void {
  let feeToken = event.params.amount0 > ZERO_BI ? _token1 : _token0;
  let feeAmount = (event.params.amount0 > ZERO_BI
    ? event.params.amount1
    : event.params.amount0)
    .times(BigInt.fromI32(event.params.fee))
    .div(BigInt.fromString("1000000"))
    .abs(); // 6 decimal places

  // todo: fee in the event is percentage, not actual value
  let feeUSD = convertTokenToUSD(feeToken, feeAmount);

  const results = _getNewPoolBalance(pool);
  const token0Balance = results[1];
  const token1Balance = results[2];


  // Calculate lending yield in USD using our helper function
  const lendingYieldUSD = calculateLendingYieldUSD(
    pool.token0Amount,
    pool.token1Amount,
    token0Balance,
    token1Balance,
    _token0,
    _token1
  );

  pool.cumulativeSwapFeeUSD = pool.cumulativeSwapFeeUSD.plus(feeUSD);
  pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(feeUSD).plus(lendingYieldUSD);
  pool.cumulativeLendingYieldUSD =
    pool.cumulativeLendingYieldUSD.plus(lendingYieldUSD);

  pool.token0Amount = token0Balance;
  pool.token1Amount = token1Balance;
  // input token amount is negative, hence we negate
  const swapVolumeUSD =
    event.params.amount0 > ZERO_BI
      ? convertTokenToUSD(_token1, event.params.amount1).neg()
      : convertTokenToUSD(_token0, event.params.amount0).neg();
  pool.cumulativeVolumeUSD = pool.cumulativeVolumeUSD.plus(swapVolumeUSD);

  const prices = sqrtPriceX96ToTokenPrices(
    event.params.sqrtPriceX96,
    _token0,
    _token1
  );
  pool.currentPrice = prices[0];

  _updateTimestamps(pool, event.block);
  bumpProtocolStats(feeUSD, swapVolumeUSD, lendingYieldUSD);

  pool.save();
}

// export function track

export function trackHookDeposit(pool: Pool, event: DepositEvent, token0: Token, token1: Token): Pool {
  let token0DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token0.decimals))
  );
  let token1DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token1.decimals))
  );

  const results = _getNewPoolBalance(pool);
  const token0Balance = results[1];
  const token1Balance = results[2];


  // Calculate lending yield in USD using our helper function
  // todo: include deposit amount here as it shouldn't be tracked as yield
  const lendingYieldUSD = calculateLendingYieldUSD(
    pool.token0Amount,
    pool.token1Amount,
    token0Balance.minus(event.params.assets0),
    token1Balance.minus(event.params.assets1),
    token0,
    token1
  );


  let depositUSD = event.params.assets0.toBigDecimal().div(token0DecimalsBD);
  depositUSD = depositUSD.plus(
    event.params.assets1.toBigDecimal().div(token1DecimalsBD)
  );

  pool.totalValueLockedUSD = pool.totalValueLockedUSD.plus(depositUSD).plus(lendingYieldUSD);
  pool.cumulativeLendingYieldUSD =
    pool.cumulativeLendingYieldUSD.plus(lendingYieldUSD);
  pool.shares = pool.shares.plus(event.params.shares);


  pool.token0Amount = token0Balance;
  pool.token1Amount = token1Balance;

  _updateTimestamps(pool, event.block);
  pool.save();

  let protocol = getOrCreateProtocol();
  protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(depositUSD);
  bumpProtocolStats(ZERO_BD, ZERO_BD, lendingYieldUSD);
  protocol.save();
  return pool;
}

export function trackHookWithdraw(pool: Pool, event: WithdrawEvent, token0: Token, token1: Token): Pool {
  let token0DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token0.decimals))
  );
  let token1DecimalsBD = new BigDecimal(
    BigInt.fromI32(10).pow(u8(token1.decimals))
  );
  
  const results = _getNewPoolBalance(pool);
  const token0Balance = results[1];
  const token1Balance = results[2];


  // Calculate lending yield in USD using our helper function
  // todo: include withdraw amount here as it shouldn't be tracked as yield
  const lendingYieldUSD = calculateLendingYieldUSD(
    pool.token0Amount,
    pool.token1Amount,
    token0Balance.plus(event.params.assets0),
    token1Balance.plus(event.params.assets1),
    token0,
    token1
  );

  let withdrawUSD = event.params.assets0.toBigDecimal().div(token0DecimalsBD);
  withdrawUSD = withdrawUSD.plus(
    event.params.assets1.toBigDecimal().div(token1DecimalsBD)
  );
  pool.shares = pool.shares.minus(event.params.shares);

  pool.totalValueLockedUSD = pool.totalValueLockedUSD.minus(withdrawUSD).plus(lendingYieldUSD);
  pool.cumulativeLendingYieldUSD =
    pool.cumulativeLendingYieldUSD.plus(lendingYieldUSD);
  pool.token0Amount = token0Balance;
  pool.token1Amount = token1Balance;

  _updateTimestamps(pool, event.block);
  pool.save();

  let protocol = getOrCreateProtocol();
  protocol.totalValueLockedUSD =
    protocol.totalValueLockedUSD.minus(withdrawUSD);
  bumpProtocolStats(ZERO_BD, ZERO_BD, lendingYieldUSD);

  protocol.save();
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
  let id: string = `${pool.id}-${idNum.toString()}`;
  let snapshot = PoolHourlySnapshots.load(id);
  if (snapshot) {
    // shouldn't happen, but just in case
    return snapshot;
  }

  const prevId = `${pool.id}-${(idNum - 1).toString()}`;
  const previousSnapshot = PoolHourlySnapshots.load(prevId);
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
  snapshot.unclaimedProtocolFeeUSD = pool.unclaimedProtocolFeeUSD;
  snapshot.claimedProtocolFeeUSD = pool.claimedProtocolFeeUSD;
  snapshot.rate = rate;
  snapshot.shares = pool.shares;
  snapshot.createdAtTimestamp = block.timestamp;
  snapshot.createdAtBlockNumber = block.number;
  snapshot.save();
  return snapshot;
}

// called once an hour by the snapshot updator
export function updatePoolLendingYield(
  pool: Pool,
  block: ethereum.Block
): BigDecimal {
  const result = _getNewPoolBalance(pool);
  const token0Balance = result[1];
  const token1Balance = result[2];


  // Get token entities for USD conversion
  const token0 = getOrCreateToken(pool.token0);
  const token1 = getOrCreateToken(pool.token1);

  // Calculate lending yield in USD using our helper function
  const lendingYieldUSD = calculateLendingYieldUSD(
    pool.token0Amount,
    pool.token1Amount,
    token0Balance,
    token1Balance,
    token0,
    token1
  );


  pool.token0Amount = token0Balance;
  pool.token1Amount = token1Balance;


  pool.cumulativeLendingYieldUSD =
    pool.cumulativeLendingYieldUSD.plus(lendingYieldUSD);
  pool.totalValueLockedUSD = lendingYieldUSD.plus(pool.totalValueLockedUSD);

  _updateTimestamps(pool, block);

  pool.save();
  return lendingYieldUSD;
}

export function trackProtocolFee(pool: Pool, event: FeesTrackedEvent): void {
  // event param tracks fee in liquidity amounts
  const feeLiquidity = event.params.feeDelta;

  // we need to convert this to token amounts
  const hookContract = HookV1.bind(Address.fromBytes(pool.hook));
  const result = hookContract.getTokenAmountsForLiquidity(feeLiquidity);
  const token0Amount = result.value0;
  const token1Amount = result.value1;
  // and then to USD

  const feeUSD = convertTokenToUSD(
    getOrCreateToken(pool.token0),
    token0Amount
  ).plus(
    convertTokenToUSD(getOrCreateToken(pool.token1), token1Amount)
  );
  pool.unclaimedProtocolFeeUSD = pool.unclaimedProtocolFeeUSD.plus(feeUSD);
  _updateTimestamps(pool, event.block);
  pool.save();

  let protocol = getOrCreateProtocol();
  protocol.cumulativeProtocolFeeUSD = protocol.cumulativeProtocolFeeUSD.plus(feeUSD);
  protocol.save();
}

export function trackFeesCollected(pool: Pool, event: FeesCollectedEvent): void {
  const token0Amount = event.params.amount0;
  const token1Amount = event.params.amount1;

  const feeUSD = convertTokenToUSD(
    getOrCreateToken(pool.token0),
    token0Amount
  ).plus(
    convertTokenToUSD(getOrCreateToken(pool.token1), token1Amount)
  );

  // we always collect all fees
  pool.unclaimedProtocolFeeUSD = ZERO_BD;
  pool.claimedProtocolFeeUSD = pool.claimedProtocolFeeUSD.plus(feeUSD);
  pool.save();
}

function _updateTimestamps(pool: Pool, block: ethereum.Block): void {
  pool.updatedAtTimestamp = block.timestamp;
  pool.updatedAtBlockNumber = block.number;
}

/**
 * Calculates lending yield in USD by accounting for different token decimals
 * @param lendingYield The total lending yield in token units
 * @param token0Balance The balance of token0
 * @param token1Balance The balance of token1
 * @param token0 Token0 entity
 * @param token1 Token1 entity
 * @returns The lending yield in USD
 */
function calculateLendingYieldUSD(
  token0BalanceBefore: BigInt,
  token1BalanceBefore: BigInt,
  token0BalanceAfter: BigInt,
  token1BalanceAfter: BigInt,
  token0: Token,
  token1: Token
): BigDecimal {
  const token0Yield = token0BalanceAfter
    .minus(token0BalanceBefore);
  const token1Yield = token1BalanceAfter
    .minus(token1BalanceBefore);

  return convertTokenToUSD(token0, token0Yield).plus(
    convertTokenToUSD(token1, token1Yield)
  );
}


function _getNewPoolBalance(
  pool: Pool,
): Array<BigInt> {
  const aToken0Contract = ERC20.bind(Address.fromString(pool.aToken0));
  const aToken1Contract = ERC20.bind(Address.fromString(pool.aToken1));
  const token0Contract = ERC20.bind(Address.fromString(pool.token0));
  const token1Contract = ERC20.bind(Address.fromString(pool.token1));

  const aToken0Balance = aToken0Contract.balanceOf(Address.fromBytes(pool.hook));
  const aToken1Balance = aToken1Contract.balanceOf(Address.fromBytes(pool.hook));
  const token0Balance = token0Contract.balanceOf(Address.fromBytes(pool.hook));
  const token1Balance = token1Contract.balanceOf(Address.fromBytes(pool.hook));

  const token0 = aToken0Balance
    .plus(token0Balance);

  const token1 = aToken1Balance
    .plus(token1Balance);

  const balance = token0
    .plus(token1);

  return [
    balance,
    token0,
    token1
  ]
}