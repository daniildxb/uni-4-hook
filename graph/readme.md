# Uniswap V4 Lending Hook Subgraph

This subgraph indexes events from the Uniswap V4 Lending Hook contract, tracking deposits, withdrawals, swaps, and lending yields.

## Indexed Data

The subgraph tracks:

### Protocol data

- Total Value Locked (TVL)
- Fees + daily/hourly snapshots
- Multiple pools (if deployed)

### Pool data

- Deposits and withdrawals
- Current liquidity
- Swap fees
- Lending yield

### User data

- Positions linked to users

### Position data

- Deposits
- Withdrawals
- Current amounts

## Data Sources and Event Handling

- **HookV1 Contract**: Tracks deposit events for user positions
- **PoolManager Contract**: Tracks initializations, liquidity changes, and swaps
- **AAVE Pool Contract**: Tracks lending activity and yield

## Entity Relationships

- Protocol -> Pools -> Positions -> Users
- Each pool tracks tokens and liquidity
- Positions track ownership and amount history
- Snapshots capture data at regular intervals

## Deployment

### Prerequisites

- Node.js and npm/yarn installed
- Access to The Graph deployment endpoint
- Contract deployed on target network

### Setup

1. Install dependencies:

```bash
cd graph
npm install
```

2. Generate AssemblyScript types from schema and ABIs:

```bash
npm run codegen
```

3. Build the subgraph:

```bash
npm run build
```

### Network Configuration

This subgraph supports deployment to multiple networks:

- Sepolia: `npm run prepare:sepolia`
- arbitrum-one: `npm run prepare:arbitrum-one`
- Mainnet: `npm run prepare:mainnet`

Each command creates a network-specific subgraph manifest.

### Deployment

Deploy to The Graph hosted service:

```bash
# For Sepolia
npm run prepare:sepolia
graph deploy --node https://api.thegraph.com/deploy/ --ipfs https://api.thegraph.com/ipfs/ <SUBGRAPH_NAME>

# For arbitrum-one
npm run prepare:arbitrum-one
graph deploy --node https://api.thegraph.com/deploy/ --ipfs https://api.thegraph.com/ipfs/ <SUBGRAPH_NAME>

# For Mainnet
npm run prepare:mainnet
graph deploy --node https://api.thegraph.com/deploy/ --ipfs https://api.thegraph.com/ipfs/ <SUBGRAPH_NAME>
```

Replace `<SUBGRAPH_NAME>` with your subgraph name on The Graph.

## Local Development

For local development, you can use Graph Node:

```bash
# Create local subgraph
npm run create-local

# Deploy to local Graph Node
npm run deploy-local
```

## Example Queries

### Get Protocol TVL and Fees

```graphql
{
  protocol(id: "uniswap-v4-lending-hook") {
    totalValueLockedUSD
    cumulativeFeeUSD
  }
}
```

### Get Pool Data

```graphql
{
  pools {
    id
    token0 {
      symbol
    }
    token1 {
      symbol
    }
    totalValueLockedUSD
    cumulativeSwapFeeUSD
    cumulativeLendingYieldUSD
  }
}
```

### Get User Positions

```graphql
{
  user(id: "0x...") {
    positions {
      pool {
        id
      }
      amount
      amountUSD
    }
  }
}
```

## Resources

- [The Graph Documentation](https://thegraph.com/docs/)
- [Uniswap V4 Documentation](https://docs.uniswap.org/concepts/protocol/v4)
- [AAVE V3 Documentation](https://docs.aave.com/developers/v/2.0/)

## References

Subgraph docs - https://thegraph.com/docs/en/subgraphs/quick-start/
Uniswap v4 subgraph - https://github.com/Uniswap/v4-subgraph
AAVE v3 subgraph - https://github.com/messari/subgraphs/tree/master/subgraphs/aave-forks/protocols/aave-v3
