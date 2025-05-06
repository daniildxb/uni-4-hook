import { Withdraw1 as WithdrawEvent } from "../../generated/HookV1/HookV1";
import { Withdrawal } from "../../generated/schema";
import { _getPositionId } from "./position";

export function createWithdraw(
  accountAddress: string,
  poolId: string,
  event: WithdrawEvent
): void {
  let positionId = _getPositionId(accountAddress, poolId);
  let withdrawalId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let withdrawal = new Withdrawal(withdrawalId);
  withdrawal.account = accountAddress;
  withdrawal.pool = poolId;
  withdrawal.position = positionId;
  withdrawal.token0Amount = event.params.assets0;
  withdrawal.token1Amount = event.params.assets1;
  withdrawal.shares = event.params.shares;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.blockNumber = event.block.number;
  withdrawal.save();
}
