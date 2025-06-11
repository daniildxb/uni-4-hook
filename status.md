Next steps:

# Things to do before launch

1. Proper testing coverage
2. Fuzzing
3. Handle supply caps on AAVE for swaps / deposits / withdrawals
4. Proper RBAC
5. Share inflation attack check

# Bug tracker

# Ops

1. Update scripts to better handle multi decimal tokens, and overall deployment flow

# Future feature ideas

1. Non-correlated pairs (via full range LPs)
1.1. Support pairs where only one token gets deposited into AAVE by specifying uint256.max buffer for the other token and allowing zero address for pools (override balance checks for aTokens to not throw)
2. Leveraged LP
3. Morpho integration


Todo:
1. Redeploy whoel setup with proper params for gho/usdc
2. Update log levels on subgraph
3. Setup arbitrager service for pools