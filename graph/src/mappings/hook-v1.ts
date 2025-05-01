import {
  Deposit1 as DepositEvent,
  Withdraw1 as WithdrawEvent,
} from "../../generated/HookV1/HookV1";
import {
  Pool,
  Account,
  Position,
  Deposit,
  Withdrawal,
} from "../../generated/schema";

export function handleDeposit(event: DepositEvent): void {
  // Load the pool (must be created during initialize event)
  // let hookAddress = event.address.toHexString();
  // todo: store poolId <> hook mapping somewhere, or emit poolId in the event
  let poolId = `0xeb4b62640827a59dd667017b5e8e14533479be83d1c7145775db1716274d4360`;
  let pool = Pool.load(poolId);

  if (pool === null) {
    // This should not happen as pool should be created during initialization
    return;
  }

  // Load or create user
  let address = event.params.owner.toHexString();
  let account = Account.load(address);
  if (address === null) {
    account = new Account(address);
    account.save();
  }

  // Create position ID
  let positionId = `${address}-${poolId}`;
  let position = Position.load(positionId);

  // create deposit entity

  // Create a new position if it doesn't exist
  if (position === null) {
    position = new Position(positionId);
    position.account = address;
    position.pool = poolId;
    position.shares = event.params.shares;
    position.createdAtTimestamp = event.block.timestamp;
    position.createdAtBlockNumber = event.block.number;
    position.updatedAtTimestamp = event.block.timestamp;
    position.updatedAtBlockNumber = event.block.number;
  } else {
    // Update position
    position.shares = position.shares.plus(event.params.shares);
    position.updatedAtTimestamp = event.block.timestamp;
    position.updatedAtBlockNumber = event.block.number;
  }

  position.save();

  // add deposit entity
  let depositId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let deposit = new Deposit(depositId);
  deposit.account = address;
  deposit.pool = poolId;
  deposit.position = positionId;
  deposit.token0Amount = event.params.assets0;
  deposit.token1Amount = event.params.assets1;
  deposit.shares = event.params.shares;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.save();

  // // Update token balances
  // todo: update pool token amounts per share
  // todo: update protocol TVL
  // updateTokenBalances(pool, token0Amount, token1Amount, true);

  // // Update TVL for pool and protocol
  // updatePoolTVL(pool, amountUSD, true);
  // updateProtocolTVL(protocol, amountUSD, true);
}

export function handleWithdraw(event: WithdrawEvent): void {
  // Load the pool (must be created during initialize event)
  // let hookAddress = event.address.toHexString();
  // todo: store poolId <> hook mapping somewhere, or emit poolId in the event
  let poolId = `0xeb4b62640827a59dd667017b5e8e14533479be83d1c7145775db1716274d4360`;

  // Load or create user
  let address = event.params.owner.toHexString();

  // Create position ID
  let positionId = `${address}-${poolId}`;
  let position = Position.load(positionId);
  if (position === null) {
    // This should not happen as pool should be created during initialization
    return;
  }

  // create deposit entity

  // Create a new position if it doesn't exist
  // Update position
  position.shares = position.shares.minus(event.params.shares);
  position.updatedAtTimestamp = event.block.timestamp;
  position.updatedAtBlockNumber = event.block.number;
  position.save();

  // add deposit entity
  let withdrawalId = `${event.transaction.hash.toHexString()}-${event.logIndex.toString()}`;
  let withdrawal = new Withdrawal(withdrawalId);
  withdrawal.account = address;
  withdrawal.pool = poolId;
  withdrawal.position = positionId;
  withdrawal.token0Amount = event.params.assets0;
  withdrawal.token1Amount = event.params.assets1;
  withdrawal.shares = event.params.shares;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.blockNumber = event.block.number;
  withdrawal.save();

  // // Update token balances
  // todo: update pool token amounts per share
  // todo: update protocol TVL
  // updateTokenBalances(pool, token0Amount, token1Amount, true);

  // // Update TVL for pool and protocol
  // updatePoolTVL(pool, amountUSD, true);
  // updateProtocolTVL(protocol, amountUSD, true);
}
