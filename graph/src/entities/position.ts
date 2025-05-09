import { Position, PositionSnapshots } from "../../generated/schema";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";
import { ethereum } from "@graphprotocol/graph-ts";
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
  position.save();
  // create empty snapshot to have a clean start
  createEmptyPositionSnapshot(position, event);
  // track first deposit
  getOrCreateSnapshot(position, event);
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

// for the initial position snapshot
export function createEmptyPositionSnapshot(position: Position, event: ethereum.Event): PositionSnapshots {
  const synthethicTimestamp = event.block.timestamp.minus(ONE_BI)
  const id = `${(synthethicTimestamp).toString()}-${event.transactionLogIndex.toString()}`;
  let snapshot = new PositionSnapshots(id);
  snapshot.shares = ZERO_BI;
  snapshot.position = position.id;
  snapshot.createdAtTimestamp = synthethicTimestamp;
  snapshot.save();
  return snapshot;
}