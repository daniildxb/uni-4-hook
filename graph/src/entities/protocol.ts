import { BigDecimal } from "@graphprotocol/graph-ts";
import { Protocol } from "../../generated/schema";
import { ZERO_BD } from "../helpers";

export function getOrCreateProtocol(): Protocol {
  let protocol = Protocol.load("uniswap-v4-lending-hook");
  if (protocol === null) {
    protocol = new Protocol("uniswap-v4-lending-hook");
    protocol.name = "Uniswap V4 Lending Hook";
    protocol.totalValueLockedUSD = ZERO_BD;
    protocol.cumulativeFeeUSD = ZERO_BD;
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
