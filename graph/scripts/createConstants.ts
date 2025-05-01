import * as fs from 'fs';
import path from 'path';
import { configs, networks } from "../src/config";
import { getNetwork } from './utils/getNetwork';
import { NetworkConfig } from '../src/config/types';

export function run(network: string) {
    const constants = configs[network];

    fs.writeFileSync(
        path.resolve(__dirname, '..', 'src', 'config', `generated/${network}.json`),
        JSON.stringify(constants, null, 2),
    )

    let wasmConstantsString = ``;

    for (const constant in constants) {
        wasmConstantsString += `export const ${constant} = "${encodeArgument(constants[constant as keyof NetworkConfig])}";\n`;
    }

    const waspConstantsPath = path.resolve(__dirname, '..', 'src', 'helpers', `constants.ts`);
    fs.writeFileSync(
        waspConstantsPath,
        wasmConstantsString
    );
}

function encodeArgument(value: any) {
    if (typeof value === 'string') {
        return `"${value}"`;
    }
    return value;
}

if (require.main === module) {
    const network = getNetwork();
    run(network);
}
