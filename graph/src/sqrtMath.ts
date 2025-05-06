import { BigInt, BigDecimal } from "@graphprotocol/graph-ts";
import { Token } from "../generated/schema";
import { ZERO_BD } from "./helpers";

const Q192 = BigInt.fromI32(2).pow(192 as u8);

export function sqrtPriceX96ToTokenPrices(
  sqrtPriceX96: BigInt,
  token0: Token,
  token1: Token
): BigDecimal[] {
  const num = sqrtPriceX96.times(sqrtPriceX96).toBigDecimal();
  const denom = BigDecimal.fromString(Q192.toString());
  const price1 = num
    .div(denom)
    .times(exponentToBigDecimal(BigInt.fromI32(token0.decimals)))
    .div(exponentToBigDecimal(BigInt.fromI32(token1.decimals)));

  const price0 = safeDiv(BigDecimal.fromString("1"), price1);
  return [price0, price1];
}

export function exponentToBigDecimal(decimals: BigInt): BigDecimal {
  let resultString = "1";

  for (let i = 0; i < decimals.toI32(); i++) {
    resultString += "0";
  }

  return BigDecimal.fromString(resultString);
}

export function safeDiv(amount0: BigDecimal, amount1: BigDecimal): BigDecimal {
  if (amount1.equals(ZERO_BD)) {
    return ZERO_BD;
  } else {
    return amount0.div(amount1);
  }
}
