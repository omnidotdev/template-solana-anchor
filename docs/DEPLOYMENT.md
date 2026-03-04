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

# 2. Deploy (auto-airdrops if balance is low)
./scripts/deploy.sh devnet --new   # First time
./scripts/deploy.sh devnet         # Upgrades

# 3. Dry run (validate without deploying)
./scripts/deploy.sh devnet --dry-run

# 4. Custom RPC endpoint
RPC_URL=https://api.devnet.solana.com ./scripts/deploy.sh devnet
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

## Buffer Recovery

Failed deployments leave behind buffer accounts that hold your SOL. The deploy script detects and offers to recover these automatically.

To recover manually:

```bash
# Check for orphaned buffers
solana program show --buffers

# Close all buffers and recover SOL
solana program close --buffers
```

## Deploy Script Flags

| Flag | Description |
|------|-------------|
| `--new` | New deployment (generates new program ID) |
| `--dry-run` | Validate everything without deploying |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `RPC_URL` | Override default RPC endpoint |
| `TREASURY_ADDRESS` | Squads multisig address (required for mainnet) |
| `ANCHOR_WALLET` | Override default wallet keypair path |

## Costs

| Action | Cost |
|--------|------|
| First deployment | ~8 SOL |
| Upgrade | ~0.01 SOL |
| Failed deploy (buffer) | Recoverable via `solana program close --buffers` |

## Troubleshooting

| Error | Fix |
|-------|-----|
| DeclaredProgramIdMismatch | Run `./scripts/deploy.sh --new` to regenerate |
| Insufficient funds | `solana airdrop 2` (devnet) or transfer SOL |
| Deployment failed | `solana program close --buffers` to recover SOL |
| Orphaned buffers | Deploy script detects these automatically |

## Commands

```bash
solana config get                 # Current network
solana balance                    # Wallet balance
solana program show <PROGRAM_ID>  # Program status
solana program show --buffers     # Check for orphaned buffers
solana program close --buffers    # Recover stuck SOL
```
