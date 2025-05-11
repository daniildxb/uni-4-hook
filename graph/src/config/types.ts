export interface NetworkConfig {
    network: string;
    HOOK_MANAGER: string;
    UNISWAP_POOL_MANAGER_ADDRESS: string;
    isLocalTest?: boolean;
    startBlock: number;
    SECONDS_IN_HOUR: number;
    SECONDS_IN_DAY: number;
}