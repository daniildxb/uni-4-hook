import { Position, PositionSnapshots } from "../../generated/schema";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";
import { ethereum } from "@graphprotocol/graph-ts";

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
  event: DepositEvent
): Position {
  let positionId = _getPositionId(accountAddress, poolId);
  let position = new Position(positionId);
  position.account = accountAddress;
  position.pool = poolId;
  position.shares = event.params.shares;
  position.createdAtTimestamp = event.block.timestamp;
  position.createdAtBlockNumber = event.block.number;
  position.updatedAtTimestamp = event.block.timestamp;
  position.updatedAtBlockNumber = event.block.number;

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
  const id = `${event.block.timestamp.toString()}-${event.transactionLogIndex.toString()}`;
  let snapshot = PositionSnapshots.load(id);
  if (snapshot) {
    return snapshot;
  }

  snapshot = new PositionSnapshots(id);
  snapshot.shares = position.shares;
  snapshot.position = position.id;
  snapshot.createdAtTimestamp = position.createdAtTimestamp;
  snapshot.save();
  return snapshot;
}