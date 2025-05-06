import { Deposit1 as DepositEvent } from "../../generated/HookV1/HookV1";
import { Deposit } from "../../generated/schema";
import { _getPositionId } from "./position";

export function createDeposit(
  accountAddress: string,
  poolId: string,
  event: DepositEvent
): void {
  let positionId = _getPositionId(accountAddress, poolId);
  let depositId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let deposit = new Deposit(depositId);
  deposit.account = accountAddress;
  deposit.pool = poolId;
  deposit.position = positionId;
  deposit.token0Amount = event.params.assets0;
  deposit.token1Amount = event.params.assets1;
  deposit.shares = event.params.shares;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.save();
}
