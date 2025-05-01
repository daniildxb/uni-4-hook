import { networks } from '../../src/config';

export function getNetwork(): string {
    const envNetwork = process.env.NETWORK;

    const argNetwork = process.argv.find(arg => networks.includes(arg));

    const network = envNetwork || argNetwork;

    if (!network) {
        throw new Error(`Network not specified. Please set NETWORK environment variable or pass it as an argument.`);
    }
    if (!networks.includes(network)) {
        throw new Error(`Invalid network specified. Available networks: ${networks.join(', ')}`);
    }
    return network;
}
