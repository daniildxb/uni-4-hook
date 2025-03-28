# Uniswap lending hook

This repo contains uniswap v4 hook that stores funds in the AAVE while they aren't used for swaps.
This allows LPs to earn both trading fees and lending yield.

By design hooks can't modify liquidity of the pool therefore LPs have to add liquidity through the hook itself to transfer ownership.
This allows the hook to
1. Deposit into AAVE after LP deposit
2. Withdraw from AAVE right before the swap
3. Deposit into AAVE after the swap happens

For simplicity reasons initial version will have couple of shortcuts:
1. Will not allow users to set their own liqudity range, instead the hook will have a single concentrated LP
2. Will only support single pair per hook


## How it works:
Hook implements ERC4626 standard to issue shares for the assets it holds.
When liquidity is added through the hook - we calculate total value in token0 using price from the pool and issue shares proportionally to the amount deposited.
With time shares gain more value as we accrue yield from AAVE and swaps and users are able to redeem them for the underlying assets.
Redeeming shares burns them and withdraws proportional amount of liquidity from AAVE to the user's wallet. Liquidity is withdrawn in both assets to avoid changing the price.


## Issues
By default pool will display 0 liquidity 'at rest' hence bots and aggregators would need some custom logic to integrate the pool.
To make sure pool earns swap fees before that happens - we need to run custom filler for UniswapX / Servo and route swaps ourselves.
Given that the pool is not expected to have high liquidity compared to the existing pools it might be best to set lower spaw fees


## Monetization options:
* Small fee on the yield
* Grant programs from AAVE or Uniswap
* Rev share from lending protocols

### Additional components needed in the long run
* Custom UI for the hooks to direct users to LP / swap through them
* UniswapX integration
* Progressive yield fee based on the tvl
* Uni v4 dynamic fee system based on volume
* Using shares as yield bearing tokens
* Allow borrowing against LP position


### Enabling users to set their own price range
To avoid DOS attacks there are multiple ways we could allow users setting their own price range

1. Personalized pools
2. Limitting amount of positions in the pool
3. Issuing shares per tick in the pool



## Commands


### Running tests

```shell
$ forge test --match-contract HookV1Test -v
```


### Running fork tests

```shell
$ forge test --match-contract HookV1Test -v --fork-url $SEPOLIA_RPC_URL --fork-block-number 7987851
```