import { run as generateTypes } from './generateTypes';
import { run as createConstants } from './createConstants';
import { run as generateYaml } from './generateYaml';
import { getNetwork } from './utils';

export function run(passedNetwork: string) {
    const network = passedNetwork || getNetwork();
    console.log(`Setting up subgraph for network: ${network}`);

    // Create constants
    createConstants(network);

    // Generate YAML files
    generateYaml(network, "subgraph");

    // Generate types
    generateTypes(network);

}
