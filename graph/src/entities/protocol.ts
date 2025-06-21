import { BigDecimal, ethereum } from "@graphprotocol/graph-ts";
import { Protocol, ProtocolHourlySnapshots } from "../../generated/schema";
import { ZERO_BD, ZERO_BI } from "../helpers";
import { SECONDS_IN_HOUR } from "../helpers/constants";

export function getOrCreateProtocol(): Protocol {
  let protocol = Protocol.load("uniswap-v4-lending-hook");
  if (protocol === null) {
    protocol = new Protocol("uniswap-v4-lending-hook");
    protocol.name = "Uniswap V4 Lending Hook";
    protocol.cumulativeFeeUSD = ZERO_BD;
    protocol.cumulativeVolumeUSD = ZERO_BD;
    protocol.cumulativeProtocolFeeUSD = ZERO_BD;
    protocol.lastSnapshotTimestamp = ZERO_BI;
    protocol.save();
  }
  return protocol;
}

// todo: check usages of this function and remove if not needed
export function bumpProtocolStats(feeToAdd: BigDecimal, swapVolumeToAdd: BigDecimal, lendingYieldToAdd: BigDecimal): void {
  let protocol = getOrCreateProtocol();
  if (protocol === null) {
    return;
  }
  protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(feeToAdd).plus(lendingYieldToAdd);
  protocol.cumulativeVolumeUSD = protocol.cumulativeVolumeUSD.plus(swapVolumeToAdd);
  protocol.save();
}

export function getOrCreateSnapshot(
  protocol: Protocol,
  block: ethereum.Block,
  protocolTvlUsd: BigDecimal,
): ProtocolHourlySnapshots {
  let id: string = (block.timestamp.toI64() / SECONDS_IN_HOUR).toString();
  let snapshot = ProtocolHourlySnapshots.load(id);
  if (snapshot) {
    return snapshot;
  }

  snapshot = new ProtocolHourlySnapshots(id);
  snapshot.protocol = protocol.id;
  snapshot.totalValueLockedUSD = protocolTvlUsd;
  snapshot.cumulativeFeeUSD = protocol.cumulativeFeeUSD;
  snapshot.cumulativeVolumeUSD = protocol.cumulativeVolumeUSD;
  snapshot.cumulativeProtocolFeeUSD = protocol.cumulativeProtocolFeeUSD;
  snapshot.createdAtTimestamp = block.timestamp;
  snapshot.createdAtBlockNumber = block.number;
  snapshot.save();
  return snapshot;
}
