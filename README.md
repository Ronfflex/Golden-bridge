# Golden Bridge

This ERC-20 token is backed to gold, with 1 token representing 1 gram of gold. Users mint tokens by sending ETH, using Chainlink Price Feeds for real-time pricing.

A 5% fee applies to mint and burn transactions, with 50% allocated to a lottery using Chainlink VRF for fairness. The token is also bridged between Ethereum and Binance Smart Chain (BSC) via Chainlink CCIP, ensuring seamless cross-chain transfers while the main implementation remains on Ethereum.
## Authors

- [@Coralie Boyer](https://github.com/coralieBo)
- [@Vincent Rainaud](https://github.com/Ronfflex)

## Installation

### Clone this repos with

```bash
git clone https://github.com/Ronfflex/Golden-bridge.git
```

## Build

### Build the code with

```bash
forge build
```
## Run 

### Run the tests with

```bash
forge test
```


### Check the coverage with

```bash
forge coverage
```

### Run the scripts with

```bash

```