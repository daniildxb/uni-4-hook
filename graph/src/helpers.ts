import { BigInt, BigDecimal, ethereum } from "@graphprotocol/graph-ts";
import {
  getOrCreateProtocol,
  getOrCreateSnapshot as protocolSnapshot,
} from "./entities/protocol";
import { getOrCreateSnapshot as poolSnapshot, updatePoolLendingYield } from "./entities/pool";
import { SECONDS_IN_HOUR } from "./helpers/constants";

export let ZERO_BI = BigInt.fromI32(0);
export let ONE_BI = BigInt.fromI32(1);
export let ZERO_BD = BigDecimal.fromString("0");
export let ONE_BD = BigDecimal.fromString("1");
export let BI_18 = BigInt.fromI32(18);

export function updateSnapshots(block: ethereum.Block): void {
  const protocol = getOrCreateProtocol();
  // check if enough time has passed to create a new snapshot
  if (
    block.timestamp
      .minus(protocol.lastSnapshotTimestamp)
      .gt(BigInt.fromI32(SECONDS_IN_HOUR))
  ) {
    // const results = protocolSnapshot(protocol, block);;
    const pools = protocol.pools.load();
    let feesUSD = ZERO_BD;
    for (let i = 0; i < pools.length; i++) {
      const pool = pools[i];
      // update pool lending yield
      feesUSD.plus(updatePoolLendingYield(pool, block));
      // snapshot 
      poolSnapshot(pool, block);
    }
    protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(feesUSD);
    protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(feesUSD);
    protocol.lastSnapshotTimestamp = block.timestamp;
    // create protocol snapshot
    protocolSnapshot(protocol, block);
    protocol.save();
  }
}
