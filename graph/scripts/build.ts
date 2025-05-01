import { run as setup } from './setup';
import { run as generateWasm } from './generateWasm';
import { run as generateYaml } from './generateYaml';
import { getNetwork } from './utils';

export async function run() {
    const network = getNetwork();
    console.log(`Building subgraph for network: ${network}`);

    // Run setup script
    await setup(network);

    // Generate WASM files
    await generateWasm(network);

    // Generate YAML files
    await generateYaml(network, "tests");
}

if (require.main === module) {
    run()
}