import { execSync } from 'child_process';
import { getNetwork } from './utils';

export function run(network: string) {
    // Generate WASM files
    execSync(`graph build src/subgraph-${network}.yaml -o build/${network}`, { stdio: 'inherit' });
}

if (require.main === module) {
    const network = getNetwork();
    run(network);
}