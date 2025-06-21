1. Issuing shares for providing full range liquidity
Single share token represents liquidty share through the whole pool
When exchange price changes so does LP position that share is entitled to


2. Issuing shares for providing Concentrated liquidity
Shares are issued per tick
If tick is out of bounds - single token is needed to LP -> mint shares
If tick is out of bounds - single token is redeemed from LP -> burnt shares

If tick is in range - both tokens are used to provide LP depending on the current price


Calculating LP position

```
const lpID = "unique";
const tickRange = [t0, ... , tmax];
let lpToken0 = 0;
let lpToken1 = 0;
for (const tick of tickRange) {
    const lpShares = getLpShares(lpID, tick);
    const [token0, token1] = getTokensPerTickPerShare(tick, lpShares);
    lpToken0 += token0;
    lpToken1 += token1;
}
```


Issuing shares during LP
```
const tickRange = [t0, ... , tmax];

```

Yield accrual
AAVE rebases aToken balance, so yield accrual mechanism is going to be the same as fee accrual from swaps