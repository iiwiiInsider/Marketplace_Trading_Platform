# PIM Network (Local ERC-20)

This folder contains a real ERC-20 **PIM** contract with a fixed max supply of **10,000,000 PIM**.

## Quick start (local)

1) Start a local chain:

```bash
cd pim-network
npx hardhat node
```

2) Deploy + sync the frontend config:

```bash
cd pim-network
npx hardhat run scripts/deploy-and-sync.js --network localhost
```

3) Serve the wallet UI:

```bash
cd ..
python3 -m http.server 8001
```

Open:
- http://localhost:8001/pim-ar-wallet/

## MetaMask

Add a network:
- RPC: http://127.0.0.1:8545
- Chain ID: 31337
- Currency: ETH

Import one of the Hardhat node accounts (shown in the `hardhat node` output) into MetaMask to have ETH for gas.

## Contract behavior

- `mint(amount)` mints to the caller (open mint), but cannot exceed max supply.
- `mintTo(to, amount)` is `onlyOwner` (owner = deployer).
