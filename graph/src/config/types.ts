export interface NetworkConfig {
    network: string;
    HOOK_MANAGER: string;
    UNISWAP_POOL_MANAGER_ADDRESS: string;
    QUOTER_ADDRESS: string;
    QUOTE_TOKEN_ADDRESS: string; // USDC or USDT depending on the network
    isLocalTest?: boolean;
    startBlock: number;
    SECONDS_IN_HOUR: number;
    SECONDS_IN_DAY: number;
}