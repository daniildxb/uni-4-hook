export interface NetworkConfig {
    network: string;
    HOOK_MANAGER: string;
    UNISWAP_POOL_MANAGER_ADDRESS: string;
    QUOTERV2_ADDRESS: string;
    QUOTERV4_ADDRESS: string;
    QUOTE_TOKEN_ADDRESS: string; // USDC or USDT depending on the network
    isLocalTest?: boolean;
    startBlock: number;
    SECONDS_IN_HOUR: number;
    SECONDS_IN_DAY: number;
}