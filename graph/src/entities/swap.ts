import { BigInt } from "@graphprotocol/graph-ts";
import { Swap as SwapEvent } from "../../generated/PoolManager/PoolManager";
import { Swap } from "../../generated/schema";

export function createSwap(event: SwapEvent): Swap {
    let swapId = event.transaction.hash.toHexString().concat('-').concat(event.logIndex.toString());
    let swap = new Swap(swapId);
    swap.pool = event.params.id.toHexString();
    swap.sender = event.params.sender;
    swap.amount0 = event.params.amount0;
    swap.amount1 = event.params.amount1;
    swap.fee = BigInt.fromI32(event.params.fee);
    swap.timestamp = event.block.timestamp;
    swap.blockNumber = event.block.number;
    swap.save();
    return swap;
}