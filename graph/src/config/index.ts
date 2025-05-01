import fs from 'fs';
import { NetworkConfig } from './types';
import { config } from 'dotenv';

const configFiles = fs
    .readdirSync(__dirname)
    .filter((file) => 
        file.endsWith('.ts') &&
    file !== 'index.ts' &&
    file !== 'types.ts' &&
    !file.startsWith('.')
);

export const configs: Record<string, NetworkConfig> = Object.fromEntries(
    configFiles.map((file) => {
        const configModule = require(`./${file.replace('.ts', '')}`);
        const config = configModule.config;
        return [config.network, config]
    })
);

export const networks = Object.values(configs).map(config => config.network);