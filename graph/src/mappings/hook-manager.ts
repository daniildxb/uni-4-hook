import { HookDeployed as HookDeployedEvent } from '../../generated/HookV1/HookManager';
import { createPoolFromHookManagerEvent } from '../entities/pool';
import { getOrCreateProtocol } from '../entities/protocol';
import { HookV1 } from '../../generated/templates';
import { log } from '@graphprotocol/graph-ts';

export function handleHookDeployed(event: HookDeployedEvent): void {
  getOrCreateProtocol();

  log.log(
    log.Level.INFO,
    `[HOOK] Hook deployed: ${event.params.hook.toHexString()}`
  );

  createPoolFromHookManagerEvent(event);
  HookV1.create(event.params.hook);
}