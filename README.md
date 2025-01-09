# Router Contract

Router contract for exchanging tokens using:
- OnchainCLOB orderbooks
- Uniswap like V2 pools
- Uniswap like V3 pools

## Requirements

```shell
npm i
forge install
```

## Build

```shell
forge build --via-ir --optimize
```

## Test

```shell
forge test --ffi -vv --via-ir --optimize --memory-limit 5368709120 --gas-limit 1125899906842624
```

## Testnet Contracts
