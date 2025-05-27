import {
  BigInt,
  BigDecimal,
  ethereum,
  Address,
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
  QUOTER_ADDRESS,
  SECONDS_IN_HOUR,
} from "./helpers/constants";
import {
  V2Quoter,
  V2Quoter__quoteExactInputSingleInputParamsStruct,
} from "../generated/PoolManager/V2Quoter";
import { ERC20 } from "../generated/HookV1/ERC20";

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
    const v2Quoter = V2Quoter.bind(Address.fromString(QUOTER_ADDRESS));
    const quoteTokenAddress = Address.fromString(QUOTE_TOKEN_ADDRESS);
    const quoteTokenContract = ERC20.bind(quoteTokenAddress);
    const quoteTokenDecimals = quoteTokenContract.decimals();
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      // if the token is the quote token, skip it
      if (token.id.toLowerCase() == quoteTokenAddress.toHexString().toLowerCase()) {
        token.lastPriceUSD = ONE_BD; // quote token price is 1
        token.save();
        continue;
      }
      const tokenPriceUSD = getTokenPrice(
        v2Quoter,
        token.id,
        token.decimals,
        quoteTokenAddress,
        quoteTokenDecimals
      );
      token.lastPriceUSD = tokenPriceUSD;
      token.save();
    }
    // const results = protocolSnapshot(protocol, block);;
    const pools = protocol.pools.load();
    let feesUSD = ZERO_BD;
    for (let i = 0; i < pools.length; i++) {
      const pool = pools[i];
      // update pool lending yield
      feesUSD = feesUSD.plus(updatePoolLendingYield(pool, block));
      // snapshot
      poolSnapshot(pool, block);
    }
    protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(feesUSD);
    protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(feesUSD);
    protocol.lastSnapshotTimestamp = block.timestamp;
    // create protocol snapshot
    protocolSnapshot(protocol, block);
    protocol.save();
  }
}

export function getTokenPrice(
  v2Quoter: V2Quoter,
  tokenAddressStr: string,
  tokenDecimals: i32,
  quoteTokenAddress: Address,
  quoteTokenDecimals: i32
): BigDecimal {
  const fees = [10, 100, 500, 3000, 10000]; // 0.05%, 0.3%, 1%

  for (let i = 0; i < fees.length; i++) {
    let tupleArray = new ethereum.Tuple();
    tupleArray.push(ethereum.Value.fromAddress(Address.fromString(tokenAddressStr)));
    tupleArray.push(ethereum.Value.fromAddress(quoteTokenAddress));
    tupleArray.push(ethereum.Value.fromUnsignedBigInt(
      BigInt.fromI32(10).pow(tokenDecimals as u8)
    ));
    tupleArray.push(ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(fees[i])));
    tupleArray.push(ethereum.Value.fromUnsignedBigInt(ZERO_BI));

    const params = changetype<V2Quoter__quoteExactInputSingleInputParamsStruct>(tupleArray);

    const quote = v2Quoter.try_quoteExactInputSingle(params);
    if (!quote.reverted) {
      // divide by quoter token decimals
      return quote.value
        .getAmountOut()
        .toBigDecimal()
        .div(new BigDecimal(BigInt.fromI32(10).pow(u8(quoteTokenDecimals))))
    }
  }
  return ZERO_BD;
}


export function getTokenPriceByAddress(address: Address): BigDecimal {
  const v2Quoter = V2Quoter.bind(Address.fromString(QUOTER_ADDRESS));
  const quoteTokenAddress = Address.fromString(QUOTE_TOKEN_ADDRESS);
  if (address.equals(quoteTokenAddress)) {
    // if the token is the quote token, return 1
    return ONE_BD;
  }
  const quoteTokenContract = ERC20.bind(quoteTokenAddress);
  const quoteTokenDecimals = quoteTokenContract.decimals();
  const tokenContract = ERC20.bind(address);
  const tokenDecimals = tokenContract.decimals();

  return getTokenPrice(v2Quoter, address.toHexString(), tokenDecimals, quoteTokenAddress, quoteTokenDecimals);
}