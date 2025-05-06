import { BigDecimal, BigInt, log } from "@graphprotocol/graph-ts";
import {
  Supply as SupplyEvent,
  Withdraw as WithdrawEvent,
} from "../../generated/AavePool/IPool";
import { Pool } from "../../generated/schema";
import { POOL_ID } from "../helpers/constants";

export function handleSupply(event: SupplyEvent): void {
  // emit Supply(params.asset, msg.sender, params.onBehalfOf, params.amount, params.referralCode);
  /*
     event Supply(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint16 indexed referralCode
  );
    */
  let poolId = POOL_ID;

  if (event.params.user.toHexString() != poolId) {
    return;
  }
  let pool = Pool.load(poolId);

  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found: ${poolId}`);
    // This should not happen as pool should be created during initialization
    return;
  }


}

export function handleWithdraw(event: WithdrawEvent): void {
  let poolId = POOL_ID;

  if (event.params.user.toHexString() != poolId) {
    return;
  }
  let pool = Pool.load(poolId);

  if (pool === null) {
    log.log(log.Level.WARNING, `[HOOK] Pool not found: ${poolId}`);
    // This should not happen as pool should be created during initialization
    return;
  }

  // check what was the last pool TVL
}
