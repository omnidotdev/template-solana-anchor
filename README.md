# ⚓ Solana Anchor Template

This is a template repository for a Solana program built with [Anchor](https://www.anchor-lang.com).

## Features

- 🚀 **Modern Stack**: Built with [Anchor](https://www.anchor-lang.com) framework for Solana program development
- 🔗 **Blockchain Ready**: Deploy to devnet or mainnet with automated scripts
- 🧪 **Testing**: Anchor test framework with TypeScript client tests
- 🔒 **Security**:
  - [Squads](https://squads.so) multisig support for upgrade authority
  - Pre-deployment validation checks
- 🛠️ **Developer Experience**:
  - Code quality with [Biome](https://biomejs.dev) for TypeScript linting
  - [Changesets](https://github.com/changesets/changesets) for versioning
  - Local validator for development
  - Easy spin up with [Tilt](https://tilt.dev)
- 🚢 **Production Ready**:
  - Automated deployment scripts
  - Pre-deploy validation
  - Upgrade support

## Prerequisites

- [Rust](https://rustup.rs)
- [Solana CLI](https://docs.solana.com/cli/install-solana-cli-tools)
- [Anchor CLI](https://www.anchor-lang.com/docs/installation)
- [Bun](https://bun.sh)

## Local Development

### Installation

```sh
bun install
tilt up
```

### Building

```sh
bun build
# or
anchor build
```

### Testing

```sh
bun test
# or
anchor test
```

### Local Validator

Start a local Solana validator:

```sh
./scripts/start-validator.sh
```

## Deployment

### Deploy to Devnet

```sh
# Get devnet SOL (repeat 4-5 times)
solana config set --url devnet
solana airdrop 2

# Deploy
./scripts/deploy.sh devnet --new
```

### Deploy to Mainnet

```sh
./scripts/deploy.sh mainnet --new
```

### Upgrade Existing Program

```sh
./scripts/deploy.sh devnet
# or
./scripts/deploy.sh mainnet
```

## Scripts

| Script | Description |
|--------|-------------|
| `deploy.sh` | Build and deploy to devnet/mainnet |
| `pre-deploy-check.sh` | Validate config before deployment |
| `start-validator.sh` | Start local Solana validator |
| `init-config.ts` | Initialize on-chain program config |

## Project Structure

```
programs/{{program-name}}/
├── src/
│   ├── lib.rs           # Program entry point
│   ├── instructions/    # Instruction handlers
│   ├── state/           # Account definitions
│   └── errors.rs        # Custom errors
scripts/
├── deploy.sh            # Deployment automation
└── ...
tests/
├── {{program-name}}.ts  # TypeScript tests
```

## Costs

| Action | Approximate Cost |
|--------|------------------|
| First deployment | ~8 SOL |
| Upgrade | ~0.01 SOL |

## Security

For mainnet deployments, use [Squads multisig](https://squads.so) to secure upgrade authority:

```sh
solana program set-upgrade-authority <PROGRAM_ID> \
  --new-upgrade-authority <SQUADS_ADDRESS>
```

## License

The code in this repository is licensed under MIT, &copy; [Omni LLC](https://omni.dev). See [LICENSE.md](LICENSE.md) for more information.
