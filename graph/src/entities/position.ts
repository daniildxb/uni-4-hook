import { Position } from "../../generated/schema";
import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";

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
}

export function trackWithdraw(position: Position, event: WithdrawEvent): void {
    position.shares = position.shares.minus(event.params.shares);
    position.updatedAtTimestamp = event.block.timestamp;
    position.updatedAtBlockNumber = event.block.number;
}

export function _getPositionId(accountAddress: string, poolId: string): string {
  return `${accountAddress}-${poolId}`;
}
