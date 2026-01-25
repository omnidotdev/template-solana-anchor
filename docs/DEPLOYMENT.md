# Deployment Guide

## Local Development

```bash
tilt up
```

## Devnet

```bash
# 1. Get SOL (~8 SOL needed)
solana config set --url devnet
solana airdrop 2  # Run 4-5 times with 30s gaps

# 2. Deploy
./scripts/deploy.sh devnet --new   # First time
./scripts/deploy.sh devnet         # Upgrades
```

## Mainnet

### Step 1: Fund Wallet

Transfer **8+ SOL** to your deployer wallet.

### Step 2: Pre-Deploy Check

```bash
./scripts/pre-deploy-check.sh mainnet
```

### Step 3: Deploy

```bash
./scripts/deploy.sh mainnet --new
```

### Step 4: Secure the Program

Transfer upgrade authority to Squads multisig:

```bash
solana program set-upgrade-authority <PROGRAM_ID> \
  --new-upgrade-authority <SQUADS_ADDRESS> \
  --url mainnet-beta
```

Then:
- Delete keypair file from computer
- Store seed phrase in physical safe

## Troubleshooting

| Error | Fix |
|-------|-----|
| DeclaredProgramIdMismatch | Run `./scripts/deploy.sh --new` to regenerate |
| Insufficient funds | `solana airdrop 2` (devnet) or transfer SOL |
| Deployment failed | `solana program close --buffers` to recover SOL |

## Costs

| Action | Cost |
|--------|------|
| First deployment | ~8 SOL |
| Upgrade | ~0.01 SOL |

## Commands

```bash
solana config get                 # Current network
solana balance                    # Wallet balance
solana program show <PROGRAM_ID>  # Program status
solana program close --buffers    # Recover stuck SOL
```
