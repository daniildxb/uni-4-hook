import { BigInt } from "@graphprotocol/graph-ts";
import { Swap as SwapEvent } from "../../generated/PoolManager/PoolManager";
import { Swap, Token } from "../../generated/schema";
import { convertTokenToUSD } from "./token";
import { ZERO_BI } from "../helpers";

export function createSwap(
  event: SwapEvent,
  token0: Token,
  token1: Token
): Swap {
  let swapId = event.transaction.hash
    .toHexString()
    .concat("-")
    .concat(event.logIndex.toString());
  let swap = new Swap(swapId);
  swap.pool = event.params.id.toHexString();
  swap.sender = event.params.sender;
  swap.token0Amount = event.params.amount0;
  swap.token1Amount = event.params.amount1;
  // to avoid double counting we need to find negative token amount and take absolute value
  swap.amountUSD = swap.token0Amount.lt(ZERO_BI) ?
    convertTokenToUSD(token0, swap.token0Amount.abs())
    : convertTokenToUSD(token1, swap.token1Amount.abs());
  swap.fee = BigInt.fromI32(event.params.fee);
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.save();
  return swap;
}
