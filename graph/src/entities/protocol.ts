import { BigDecimal, ethereum } from "@graphprotocol/graph-ts";
import { Protocol, ProtocolHourlySnapshots } from "../../generated/schema";
import { ZERO_BD, ZERO_BI } from "../helpers";
import { SECONDS_IN_HOUR } from "../helpers/constants";

export function getOrCreateProtocol(): Protocol {
  let protocol = Protocol.load("uniswap-v4-lending-hook");
  if (protocol === null) {
    protocol = new Protocol("uniswap-v4-lending-hook");
    protocol.name = "Uniswap V4 Lending Hook";
    protocol.totalValueLockedUSD = ZERO_BD;
    protocol.cumulativeFeeUSD = ZERO_BD;
    protocol.lastSnapshotTimestamp = ZERO_BI;
    protocol.save();
  }
  return protocol;
}

export function bumpFeesAndTVL(assets: BigDecimal): void {
  let protocol = getOrCreateProtocol();
  if (protocol === null) {
    return;
  }
  protocol.totalValueLockedUSD = protocol.totalValueLockedUSD.plus(assets);
  protocol.cumulativeFeeUSD = protocol.cumulativeFeeUSD.plus(assets);
  protocol.save();
}

export function getOrCreateSnapshot(
  protocol: Protocol,
  block: ethereum.Block
): ProtocolHourlySnapshots {
  let id: string = (block.timestamp.toI64() / SECONDS_IN_HOUR).toString();
  let snapshot = ProtocolHourlySnapshots.load(id);
  if (snapshot) {
    return snapshot;
  }

  // update protocol TVL and 

  snapshot = new ProtocolHourlySnapshots(id);
  snapshot.protocol = protocol.id;
  snapshot.totalValueLockedUSD = protocol.totalValueLockedUSD;
  snapshot.cumulativeFeeUSD = protocol.cumulativeFeeUSD;
  snapshot.save();
  return snapshot;
}
