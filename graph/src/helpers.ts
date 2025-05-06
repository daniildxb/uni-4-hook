import { BigInt, BigDecimal, ethereum } from '@graphprotocol/graph-ts';
import { getOrCreateProtocol, getOrCreateSnapshot as protocolSnapshot } from './entities/protocol';
import { getOrCreateSnapshot as poolSnapshot } from './entities/pool';

export let ZERO_BI = BigInt.fromI32(0);
export let ONE_BI = BigInt.fromI32(1);
export let ZERO_BD = BigDecimal.fromString('0');
export let ONE_BD = BigDecimal.fromString('1');
export let BI_18 = BigInt.fromI32(18);

export function updateSnapshots(block: ethereum.Block): void {
    const protocol = getOrCreateProtocol();
    protocolSnapshot(protocol, block);
    const pools = protocol.pools.load();

    for (let i = 0; i < pools.length; i++) {
        const pool = pools[i];
        poolSnapshot(pool, block);
    }
}