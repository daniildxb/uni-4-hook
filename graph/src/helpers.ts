import {
  BigInt,
  BigDecimal,
  ethereum,
  Address,
  log,
  Bytes,
} from "@graphprotocol/graph-ts";
import {
  getOrCreateProtocol,
  getOrCreateSnapshot as protocolSnapshot,
} from "./entities/protocol";
import {
  getOrCreateSnapshot as poolSnapshot,
  updatePoolLendingYield,
} from "./entities/pool";
import {
  QUOTE_TOKEN_ADDRESS,
  QUOTERV2_ADDRESS,
  QUOTERV4_ADDRESS,
  SECONDS_IN_HOUR,
} from "./helpers/constants";
import {
  V2Quoter,
  V2Quoter__quoteExactInputSingleInputParamsStruct,
} from "../generated/PoolManager/V2Quoter";
import {
  V4Quoter,
  V4Quoter__quoteExactInputSingleInputParamsStruct,
} from "../generated/PoolManager/V4Quoter";
import { ERC20 } from "../generated/HookV1/ERC20";
import { Token } from "../generated/schema";

export let ZERO_BI = BigInt.fromI32(0);
export let ONE_BI = BigInt.fromI32(1);
export let ZERO_BD = BigDecimal.fromString("0");
export let ONE_BD = BigDecimal.fromString("1");
export let BI_18 = BigInt.fromI32(18);

export function updateSnapshots(block: ethereum.Block): void {
  const protocol = getOrCreateProtocol();
  // check if enough time has passed to create a new snapshot
  if (
    block.timestamp
      .minus(protocol.lastSnapshotTimestamp)
      .gt(BigInt.fromI32(SECONDS_IN_HOUR))
  ) {
    // firstly update token prices
    const tokens = protocol.tokens.load();
    const quoteTokenAddress = Address.fromString(QUOTE_TOKEN_ADDRESS);
    const quoteTokenContract = ERC20.bind(quoteTokenAddress);
    const quoteTokenDecimals = quoteTokenContract.decimals();
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      // if the token is the quote token, skip it
      if (
        token.id.toLowerCase() == quoteTokenAddress.toHexString().toLowerCase()
      ) {
        token.lastPriceUSD = ONE_BD; // quote token price is 1
        token.save();
        continue;
      }
      const tokenPriceUSD = getTokenPrice(
        token.id,
        token.decimals,
        quoteTokenAddress,
        quoteTokenDecimals
      );
      token.lastPriceUSD = tokenPriceUSD;
      token.save();
    }
    const pools = protocol.pools.load();
    let feesUSD = ZERO_BD;
    let protocolTvlUsd = ZERO_BD;
    for (let i = 0; i < pools.length; i++) {
      const pool = pools[i];
      // update pool lending yield
      feesUSD = feesUSD.plus(updatePoolLendingYield(pool, block));
      // snapshot

      let token0: Token | null = null;
      let token1: Token | null = null;
      for (let j = 0; j < tokens.length; j++) {
        if (tokens[j].id.toLowerCase() == pool.token0.toLowerCase()) {
          token0 = tokens[j];
        }
        if (tokens[j].id.toLowerCase() == pool.token1.toLowerCase()) {
          token1 = tokens[j];
        }
      }
      if (!token0 || !token1) {
        continue; // skip if tokens are not found
      }
      const snapshot = poolSnapshot(pool, block, token0, token1);
      protocolTvlUsd = protocolTvlUsd.plus(snapshot.totalValueLockedUSD);
    }
    protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(feesUSD);
    protocol.lastSnapshotTimestamp = block.timestamp;
    // create protocol snapshot
    protocolSnapshot(protocol, block, protocolTvlUsd);
    protocol.save();
  }
}

// todo: need to find a more reliable way to get token prices
// todo: add quoterv4 support
export function getTokenPrice(
  tokenAddressStr: string,
  tokenDecimals: i32,
  quoteTokenAddress: Address,
  quoteTokenDecimals: i32
): BigDecimal {
  let quote = _getQuoteFromQuoterV2(
    tokenAddressStr,
    tokenDecimals,
    quoteTokenAddress,
    quoteTokenDecimals
  );
  if (quote.equals(ZERO_BD)) {
    quote = _getQuoteFromQuoterV4(
      tokenAddressStr,
      tokenDecimals,
      quoteTokenAddress,
      quoteTokenDecimals
    );
  }
  return quote;
}

function _getQuoteFromQuoterV2(
  tokenAddressStr: string,
  tokenDecimals: i32,
  quoteTokenAddress: Address,
  quoteTokenDecimals: i32
): BigDecimal {
  const v2Quoter = V2Quoter.bind(Address.fromString(QUOTERV2_ADDRESS));
  const fees = [10, 100, 500, 3000, 10000]; // 0.001%, 0.01% 0.05%, 0.3%, 1%

  for (let i = 0; i < fees.length; i++) {
    let tupleArray = new ethereum.Tuple();
    tupleArray.push(
      ethereum.Value.fromAddress(Address.fromString(tokenAddressStr))
    );
    tupleArray.push(ethereum.Value.fromAddress(quoteTokenAddress));
    tupleArray.push(
      ethereum.Value.fromUnsignedBigInt(
        BigInt.fromI32(10).pow(tokenDecimals as u8)
      )
    );
    tupleArray.push(ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(fees[i])));
    tupleArray.push(ethereum.Value.fromUnsignedBigInt(ZERO_BI));

    const params =
      changetype<V2Quoter__quoteExactInputSingleInputParamsStruct>(tupleArray);

    const quote = v2Quoter.try_quoteExactInputSingle(params);
    if (!quote.reverted) {
      // divide by quoter token decimals
      return quote.value
        .getAmountOut()
        .toBigDecimal()
        .div(new BigDecimal(BigInt.fromI32(10).pow(u8(quoteTokenDecimals))));
    }
  }
  log.warning("_getQuoteFromQuoterV2: could not get price for token: {}", [
    tokenAddressStr,
  ]);
  // if no price was found, return 0
  return ZERO_BD;
}


function _getQuoteFromQuoterV4(
  tokenAddressStr: string,
  tokenDecimals: i32,
  quoteTokenAddress: Address,
  quoteTokenDecimals: i32
): BigDecimal {
  const v4Quoter = V4Quoter.bind(Address.fromString(QUOTERV4_ADDRESS));
  const fees = [10, 100, 500, 3000, 10000]; // 0.001%, 0.01% 0.05%, 0.3%, 1%
  const tickSpacings = [1, 10, 20, 30, 40, 50, 60, 100, 120, 150, 200]; // corresponding tick spacings for the fees
  const normalizedQuoteTokenAddress = quoteTokenAddress.toHexString().toLowerCase();
  const token0 = tokenAddressStr.toLowerCase() < normalizedQuoteTokenAddress ? tokenAddressStr.toLowerCase() : normalizedQuoteTokenAddress;
  const token1 = tokenAddressStr.toLowerCase() < normalizedQuoteTokenAddress ? normalizedQuoteTokenAddress : tokenAddressStr.toLowerCase();
  // for quote we check price of token0 in quoteToken
  // hence if token0 is quote, we want to swap token1 for quote -> zeroForOne = false
  const zeroForOne = normalizedQuoteTokenAddress != token0;

  for (let i = 0; i < fees.length; i++) {
    for (let j = 0; j < tickSpacings.length; j++) {
      // Construct the nested tuple for the first argument
      let innerTuple = new ethereum.Tuple();
      innerTuple.push(ethereum.Value.fromAddress(Address.fromString(token0))); // token0
      innerTuple.push(ethereum.Value.fromAddress(Address.fromString(token1))); // token1
      innerTuple.push(ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(fees[i]))); // fee (uint24)
      innerTuple.push(ethereum.Value.fromSignedBigInt(BigInt.fromI32(tickSpacings[j]))); // tickSpacing (int24)
      innerTuple.push(ethereum.Value.fromAddress(Address.zero())); // hook

      let paramsTuple = new ethereum.Tuple();
      paramsTuple.push(ethereum.Value.fromTuple(innerTuple)); // struct PoolKey
      paramsTuple.push(ethereum.Value.fromBoolean(zeroForOne)); // zeroForOne
      paramsTuple.push(ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(10).pow(tokenDecimals as u8))); // exactAmount (uint128)
      paramsTuple.push(ethereum.Value.fromBytes(Bytes.empty())); // bytes

      const params =
        changetype<V4Quoter__quoteExactInputSingleInputParamsStruct>(paramsTuple);

      const quote = v4Quoter.try_quoteExactInputSingle(params);
      if (!quote.reverted) {
        // divide by quoter token decimals
        return quote.value
          .getAmountOut()
          .toBigDecimal()
          .div(new BigDecimal(BigInt.fromI32(10).pow(u8(quoteTokenDecimals))));
      }
    }
  }
  log.warning("_getQuoteFromQuoterV4: could not get price for token: {}", [
    tokenAddressStr,
  ]);
  // if no price was found, return 0
  return ZERO_BD;
}

export function getTokenPriceByAddress(address: Address): BigDecimal {
  const quoteTokenAddress = Address.fromString(QUOTE_TOKEN_ADDRESS);
  if (address.equals(quoteTokenAddress)) {
    // if the token is the quote token, return 1
    return ONE_BD;
  }
  const quoteTokenContract = ERC20.bind(quoteTokenAddress);
  const quoteTokenDecimals = quoteTokenContract.decimals();
  const tokenContract = ERC20.bind(address);
  const tokenDecimals = tokenContract.decimals();

  return getTokenPrice(
    address.toHexString(),
    tokenDecimals,
    quoteTokenAddress,
    quoteTokenDecimals
  );
}
