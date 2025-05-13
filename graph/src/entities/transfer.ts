import { Address } from "@graphprotocol/graph-ts";
import { HookV1, Transfer as TransferEvent } from "../../generated/HookV1/HookV1";
import { Pool, Transfer } from "../../generated/schema";
import { _getPositionId } from "./position";
import { convertTokenToUSD, getOrCreateToken } from "./token";

export function createTransfer(
  pool: Pool,
  event: TransferEvent,
): void {
  const hookContract = HookV1.bind(Address.fromBytes(pool.hook));
  const result = hookContract.getTokenAmountsForLiquidity(event.params.value);
  const token0Amount = result.value0.abs();
  const token1Amount = result.value1.abs();

  const token0 = getOrCreateToken(pool.token0);
  const token1 = getOrCreateToken(pool.token1);

  const amountUSD = convertTokenToUSD(token0, token0Amount).plus(
    convertTokenToUSD(token1, token1Amount)
  );

  
  let positionId = _getPositionId(event.params.from.toHexString(), pool.id);
  let transferId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let transfer = new Transfer(transferId);
  transfer.sender = event.params.from.toHexString();
  transfer.receiver = event.params.to.toHexString();
  transfer.pool = pool.id;
  transfer.position = positionId;
  transfer.token0Amount = token0Amount;
  transfer.token1Amount = token1Amount;
  transfer.shares = event.params.value;
  transfer.amountUSD = amountUSD;
  transfer.timestamp = event.block.timestamp;
  transfer.blockNumber = event.block.number;
  transfer.save();
}
