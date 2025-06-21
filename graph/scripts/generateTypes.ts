import { execSync } from 'child_process';
import { getNetwork } from './utils';

export function run(network: string) {
    execSync(`graph codegen src/subgraph-${network}.yaml`, { stdio: 'inherit' });
}

if (require.main === module) {
    const network = getNetwork();
    run(network);
}