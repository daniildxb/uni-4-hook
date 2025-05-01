import { execSync, exec } from 'child_process';
import { getNetwork } from './utils';

export function run(network: string, type: string) {
    if (!type || !["tests", "subgraph"].includes(type)) {
        throw new Error(`Invalid type: ${type}. Expected "tests" or "subgraph".`);
    }

    const template = 
      type === "tests"
        ? "matchstick.template.yaml"
        : "src/subgraph.template.yaml";
    
    const output = type === "tests" ? "matchstick.yaml" : `src/subgraph-${network}.yaml`;

    execSync(`mustache src/config/generated/${network}.json ${template} > ${output}`, { stdio: 'inherit' });
}

if (require.main === module) {
    const network = getNetwork();
    run(network, "tests");
}