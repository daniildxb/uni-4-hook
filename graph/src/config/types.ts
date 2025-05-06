export interface NetworkConfig {
    network: string;
    HOOK_ADDRESS: string;
    POOL_ID: string;
    UNISWAP_POOL_MANAGER_ADDRESS: string;
    AAVE_POOL_ADDRESS: string;
    isLocalTest?: boolean;
    startBlock: number;
    SECONDS_IN_HOUR: number;
    SECONDS_IN_DAY: number;
}