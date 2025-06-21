import { Pool, Position, PositionSnapshots } from "../../generated/schema";
import {
  Deposit1 as DepositEvent,
  Transfer as TransferEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";
import { ethereum, BigInt } from "@graphprotocol/graph-ts";
import { ONE_BI, ZERO_BI } from "../helpers";

export function getPosition(
  accountAddress: string,
  poolId: string
): Position | null {
  let positionId = _getPositionId(accountAddress, poolId);
  return Position.load(positionId);
}

export function createPosition(
  accountAddress: string,
  poolId: string,
  shares: BigInt,
  event: ethereum.Event
): Position {
  let positionId = _getPositionId(accountAddress, poolId);
  let position = new Position(positionId);
  position.account = accountAddress;
  position.pool = poolId;
  position.shares = shares;
  position.createdAtTimestamp = event.block.timestamp;
  position.createdAtBlockNumber = event.block.number;
  position.updatedAtTimestamp = event.block.timestamp;
  position.updatedAtBlockNumber = event.block.number;
  position.save();
  // track first deposit
  getOrCreateSnapshot(position, event);
  return position;
}

export function getOrCreatePosition(
  accountAddress: string,
  poolId: string,
  shares: BigInt,
  event: ethereum.Event): Position {
  let position = getPosition(accountAddress, poolId);
  if (position === null) {
    position = createPosition(accountAddress, poolId, shares, event);
  }
  return position;
}

export function trackDeposit(position: Position, event: DepositEvent): void {
  position.shares = position.shares.plus(event.params.shares);
  position.updatedAtTimestamp = event.block.timestamp;
  position.updatedAtBlockNumber = event.block.number;
  position.save();
  getOrCreateSnapshot(position, event);
}

export function trackWithdraw(position: Position, event: WithdrawEvent): void {
    position.shares = position.shares.minus(event.params.shares);
    position.updatedAtTimestamp = event.block.timestamp;
    position.updatedAtBlockNumber = event.block.number;
    position.save();
    getOrCreateSnapshot(position, event);
}

export function _getPositionId(accountAddress: string, poolId: string): string {
  return `${accountAddress}-${poolId}`;
}

// need to handle multiple transactions in the same block, to do so we need to 
export function getOrCreateSnapshot(position: Position, event: ethereum.Event): PositionSnapshots {
  const id = `${position.id}-${event.transaction.hash.toHexString()}-${event.transactionLogIndex.toString()}`;
  let snapshot = PositionSnapshots.load(id);
  if (snapshot) {
    return snapshot;
  }

  snapshot = new PositionSnapshots(id);
  snapshot.shares = position.shares;
  snapshot.position = position.id;
  snapshot.createdAtTimestamp = event.block.timestamp;
  snapshot.createdAtBlockNumber = event.block.number;
  snapshot.save();
  return snapshot;
}

export function trackTransfer(
  fromAddress: string,
  toAddress: string,
  pool: Pool,
  event: TransferEvent
): void {
  const fromPosition = getPosition(fromAddress, pool.id);
  if (fromPosition === null) {
    // shouldn't happen unless the position was created and transfered in the same TX
    return;
  }

  fromPosition.shares = fromPosition.shares.minus(event.params.value);
  fromPosition.updatedAtTimestamp = event.block.timestamp;
  fromPosition.updatedAtBlockNumber = event.block.number;
  fromPosition.save();

  const toPosition = getOrCreatePosition(toAddress, pool.id, event.params.value, event);

  toPosition.shares = toPosition.shares.plus(event.params.value);
  toPosition.updatedAtTimestamp = event.block.timestamp;
  toPosition.updatedAtBlockNumber = event.block.number;
  toPosition.save();
  getOrCreateSnapshot(fromPosition, event);
  getOrCreateSnapshot(toPosition, event);

}