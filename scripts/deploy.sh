#!/bin/bash
set -e

# =============================================================================
# SOLANA DEPLOY SCRIPT
# =============================================================================
# Usage:
#   ./scripts/deploy.sh devnet            # Upgrade existing devnet deployment
#   ./scripts/deploy.sh devnet --new      # New devnet deployment (new program ID)
#   ./scripts/deploy.sh devnet --dry-run  # Validate everything without deploying
#   ./scripts/deploy.sh mainnet           # Mainnet deployment
#
# Environment:
#   TREASURY_ADDRESS  - Required for mainnet (Squads multisig address)
#   RPC_URL           - Override default RPC endpoint
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NETWORK="${1:-devnet}"
NEW_DEPLOYMENT=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --new)
            NEW_DEPLOYMENT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
    esac
done

if [[ "$NETWORK" != "devnet" && "$NETWORK" != "mainnet" ]]; then
    echo -e "${RED}Usage: $0 <devnet|mainnet> [--new] [--dry-run]${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Get program name from Anchor.toml
PROGRAM_NAME=$(grep -A1 "\[programs.localnet\]" Anchor.toml | tail -1 | cut -d'=' -f1 | tr -d ' ')

DRY_RUN_LABEL=""
if [[ "$DRY_RUN" == true ]]; then
    DRY_RUN_LABEL=" (DRY RUN)"
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    SOLANA DEPLOYMENT${DRY_RUN_LABEL}$(printf '%*s' $((26 - ${#DRY_RUN_LABEL})) '')║${NC}"
echo -e "${BLUE}║                    Network: ${NETWORK}$(printf '%*s' $((33 - ${#NETWORK})) '')║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1: CONFIGURE NETWORK
# =============================================================================
echo -e "${YELLOW}[1/9] Configuring network...${NC}"

if [[ -n "$RPC_URL" ]]; then
    echo -e "${GREEN}      ✓ Using RPC override: $RPC_URL${NC}"
elif [[ "$NETWORK" == "mainnet" ]]; then
    RPC_URL="https://api.mainnet-beta.solana.com"
else
    RPC_URL="https://api.devnet.solana.com"
fi

solana config set --url "$RPC_URL" > /dev/null
echo -e "${GREEN}      ✓ Set to $NETWORK ($RPC_URL)${NC}"

# =============================================================================
# STEP 2: WALLET INFO
# =============================================================================
echo -e "${YELLOW}[2/9] Checking wallet...${NC}"

WALLET_PATH="${ANCHOR_WALLET:-$(solana config get | grep "Keypair Path" | awk '{print $3}')}"
WALLET_ADDRESS=$(solana address -k "$WALLET_PATH" 2>/dev/null || solana address)
BALANCE=$(solana balance "$WALLET_ADDRESS" | awk '{print $1}')

echo "      Wallet: $WALLET_ADDRESS"
echo "      Balance: $BALANCE SOL"
echo -e "${GREEN}      ✓ Wallet OK${NC}"

# =============================================================================
# STEP 3: MAINNET SAFETY CHECKS
# =============================================================================
if [[ "$NETWORK" == "mainnet" ]]; then
    echo -e "${YELLOW}[3/9] Mainnet safety checks...${NC}"

    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo -e "${RED}      ╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}      ║  MAINNET DEPLOYMENT - THIS COSTS REAL MONEY (~\$1,500)    ║${NC}"
        echo -e "${RED}      ╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -p "      Type 'deploy mainnet' to confirm: " CONFIRM
        if [[ "$CONFIRM" != "deploy mainnet" ]]; then
            echo "      Aborted."
            exit 1
        fi
    else
        echo -e "${YELLOW}      Skipping mainnet confirmation (dry run)${NC}"
    fi
else
    echo -e "${YELLOW}[3/9] Safety checks...${NC}"
    echo -e "${GREEN}      ✓ Devnet deployment${NC}"
fi

# =============================================================================
# STEP 4: SETUP PROGRAM ID
# =============================================================================
echo -e "${YELLOW}[4/9] Program ID setup...${NC}"

if [[ "$NETWORK" == "mainnet" ]]; then
    KEYPAIR_PATH="target/deploy/${PROGRAM_NAME}_mainnet-keypair.json"
else
    KEYPAIR_PATH="target/deploy/${PROGRAM_NAME}-keypair.json"
fi

if [[ "$NEW_DEPLOYMENT" == true ]]; then
    echo "      Creating new program keypair..."

    if [[ -f "$KEYPAIR_PATH" ]]; then
        echo -e "${YELLOW}      Existing keypair found. Backing up...${NC}"
        mv "$KEYPAIR_PATH" "${KEYPAIR_PATH}.backup.$(date +%s)"
    fi

    mkdir -p "$(dirname "$KEYPAIR_PATH")"
    solana-keygen new -o "$KEYPAIR_PATH" --no-bip39-passphrase --force

    PROGRAM_ID=$(solana address -k "$KEYPAIR_PATH")
    echo ""
    echo -e "${GREEN}      New Program ID: $PROGRAM_ID${NC}"
    echo ""

    if [[ "$NETWORK" == "mainnet" ]]; then
        echo -e "${RED}      SAVE THE SEED PHRASE ABOVE! Store it offline.${NC}"
        read -p "      Press Enter after saving the seed phrase..."
    fi

    # Update config files
    echo "      Updating configuration files..."

    # lib.rs
    sed -i "s/declare_id!(\"[^\"]*\")/declare_id!(\"$PROGRAM_ID\")/" "programs/${PROGRAM_NAME}/src/lib.rs"

    # Anchor.toml
    if [[ "$NETWORK" == "mainnet" ]]; then
        sed -i "/\[programs.mainnet\]/,/\[/ s/${PROGRAM_NAME} = \"[^\"]*\"/${PROGRAM_NAME} = \"$PROGRAM_ID\"/" "Anchor.toml"
    else
        sed -i "/\[programs.devnet\]/,/\[/ s/${PROGRAM_NAME} = \"[^\"]*\"/${PROGRAM_NAME} = \"$PROGRAM_ID\"/" "Anchor.toml"
        sed -i "/\[programs.localnet\]/,/\[/ s/${PROGRAM_NAME} = \"[^\"]*\"/${PROGRAM_NAME} = \"$PROGRAM_ID\"/" "Anchor.toml"
    fi

    # init-config.ts
    sed -i "s/\"[A-Za-z0-9]\{32,44\}\",$/\"$PROGRAM_ID\",/" "scripts/init-config.ts" 2>/dev/null || true

    echo -e "${GREEN}      ✓ All config files updated${NC}"
else
    if [[ ! -f "$KEYPAIR_PATH" ]]; then
        echo -e "${RED}      ✗ No keypair found at $KEYPAIR_PATH${NC}"
        echo "      Run with --new flag for first deployment: $0 $NETWORK --new"
        exit 1
    fi
    PROGRAM_ID=$(solana address -k "$KEYPAIR_PATH")
    echo -e "${GREEN}      ✓ Using existing Program ID: $PROGRAM_ID${NC}"
fi

# =============================================================================
# STEP 5: BUILD
# =============================================================================
echo -e "${YELLOW}[5/9] Building program...${NC}"

if [[ "$NETWORK" == "mainnet" ]]; then
    anchor build --verifiable 2>&1 | tail -3
else
    anchor build 2>&1 | tail -3
fi
echo -e "${GREEN}      ✓ Build complete${NC}"

# =============================================================================
# STEP 6: CHECK FOR ORPHANED BUFFERS
# =============================================================================
echo -e "${YELLOW}[6/9] Checking for orphaned buffers...${NC}"

BUFFER_OUTPUT=$(solana program show --buffers 2>/dev/null || echo "")
BUFFER_COUNT=$(echo "$BUFFER_OUTPUT" | grep -c "^[A-Za-z0-9]" || echo "0")

if [[ "$BUFFER_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}      ⚠ Found $BUFFER_COUNT orphaned buffer(s):${NC}"
    echo "$BUFFER_OUTPUT" | grep "^[A-Za-z0-9]" | while read -r line; do
        BUFFER_ADDR=$(echo "$line" | awk '{print $1}')
        echo "        - $BUFFER_ADDR"
    done

    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        read -p "      Close buffers and recover SOL? (y/N): " RECOVER
        if [[ "$RECOVER" == "y" || "$RECOVER" == "Y" ]]; then
            echo "      Closing buffers..."
            solana program close --buffers
            BALANCE=$(solana balance "$WALLET_ADDRESS" | awk '{print $1}')
            echo -e "${GREEN}      ✓ Buffers closed. New balance: $BALANCE SOL${NC}"
        fi
    else
        echo -e "${YELLOW}      Skipping buffer recovery (dry run)${NC}"
        echo "      To recover manually: solana program close --buffers"
    fi
else
    echo -e "${GREEN}      ✓ No orphaned buffers${NC}"
fi

# =============================================================================
# STEP 7: COST ESTIMATE & BALANCE CHECK
# =============================================================================
echo -e "${YELLOW}[7/9] Estimating cost & checking balance...${NC}"

# Check if program already exists on chain
PROGRAM_EXISTS=$(solana program show "$PROGRAM_ID" 2>/dev/null | grep -c "Program Id" || echo "0")

# Refresh balance
BALANCE=$(solana balance "$WALLET_ADDRESS" | awk '{print $1}')
BALANCE_INT=${BALANCE%.*}

# Calculate estimated cost from binary size
SO_PATH="target/deploy/${PROGRAM_NAME}.so"
if [[ -f "$SO_PATH" ]]; then
    SO_BYTES=$(wc -c < "$SO_PATH")
    # Solana charges rent for 2x program size (for buffer during deploy)
    ESTIMATED_COST=$(awk "BEGIN { printf \"%.2f\", ($SO_BYTES * 2 * 6960 / 1000000000) + 0.5 }")
else
    ESTIMATED_COST="unknown"
fi

if [[ "$PROGRAM_EXISTS" == "0" || "$NEW_DEPLOYMENT" == true ]]; then
    DEPLOY_TYPE="New deployment"
    REQUIRED_SOL=8
else
    DEPLOY_TYPE="Upgrade"
    REQUIRED_SOL=1
    ESTIMATED_COST="~0.01"
fi

REMAINING=$(awk "BEGIN { printf \"%.2f\", $BALANCE - ${ESTIMATED_COST:-0} }")

echo ""
echo "      ┌──────────────────┬──────────────────┐"
echo "      │ Type             │ $DEPLOY_TYPE$(printf '%*s' $((17 - ${#DEPLOY_TYPE})) '')│"
echo "      │ Current balance  │ $BALANCE SOL$(printf '%*s' $((13 - ${#BALANCE})) '')│"
echo "      │ Estimated cost   │ ~$ESTIMATED_COST SOL$(printf '%*s' $((12 - ${#ESTIMATED_COST})) '')│"
echo "      │ Remaining after  │ ~$REMAINING SOL$(printf '%*s' $((12 - ${#REMAINING})) '')│"
echo "      └──────────────────┴──────────────────┘"
echo ""

if [[ "$BALANCE_INT" -lt "$REQUIRED_SOL" ]]; then
    echo -e "${RED}      ✗ Insufficient balance. Need $REQUIRED_SOL SOL (have $BALANCE SOL).${NC}"

    if [[ "$NETWORK" == "devnet" ]]; then
        echo "      Attempting devnet airdrop..."
        for i in $(seq 1 5); do
            echo "      Airdrop attempt $i/5..."
            if solana airdrop 2 2>/dev/null; then
                sleep 2
                BALANCE=$(solana balance "$WALLET_ADDRESS" | awk '{print $1}')
                BALANCE_INT=${BALANCE%.*}
                echo -e "${GREEN}      ✓ Airdrop received. Balance: $BALANCE SOL${NC}"
                if [[ "$BALANCE_INT" -ge "$REQUIRED_SOL" ]]; then
                    break
                fi
            else
                echo -e "${YELLOW}      Airdrop failed, retrying in 15s...${NC}"
                sleep 15
            fi
        done

        # Recheck after airdrops
        BALANCE=$(solana balance "$WALLET_ADDRESS" | awk '{print $1}')
        BALANCE_INT=${BALANCE%.*}
        if [[ "$BALANCE_INT" -lt "$REQUIRED_SOL" ]]; then
            echo -e "${RED}      ✗ Still insufficient after airdrops. Need $REQUIRED_SOL SOL (have $BALANCE SOL).${NC}"
            exit 1
        fi
    else
        exit 1
    fi
fi

if [[ "$NETWORK" == "devnet" && "$DRY_RUN" != true ]]; then
    REMAINING=$(awk "BEGIN { printf \"%.2f\", $BALANCE - ${ESTIMATED_COST:-0} }")
    echo -e "${YELLOW}      This will cost ~$ESTIMATED_COST SOL. You'll have ~$REMAINING SOL remaining.${NC}"
    read -p "      Continue? (Y/n): " COST_CONFIRM
    if [[ "$COST_CONFIRM" == "n" || "$COST_CONFIRM" == "N" ]]; then
        echo "      Aborted."
        exit 1
    fi
fi

echo -e "${GREEN}      ✓ Balance OK${NC}"

# =============================================================================
# STEP 8: DEPLOY
# =============================================================================
echo -e "${YELLOW}[8/9] Deploying to $NETWORK...${NC}"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}      Skipping deployment (dry run)${NC}"
else
    if [[ "$PROGRAM_EXISTS" == "0" || "$NEW_DEPLOYMENT" == true ]]; then
        echo "      First-time deployment..."
        if [[ "$NETWORK" == "mainnet" ]]; then
            anchor deploy --provider.cluster mainnet --program-keypair "$KEYPAIR_PATH" --provider.wallet "$WALLET_PATH"
        else
            anchor deploy --provider.cluster devnet --provider.wallet "$WALLET_PATH"
        fi
    else
        echo "      Upgrading existing program..."
        anchor upgrade target/deploy/${PROGRAM_NAME}.so \
            --program-id "$PROGRAM_ID" \
            --provider.cluster "$NETWORK" \
            --provider.wallet "$WALLET_PATH"
    fi

    POST_BALANCE=$(solana balance "$WALLET_ADDRESS" | awk '{print $1}')
    ACTUAL_COST=$(awk "BEGIN { printf \"%.2f\", $BALANCE - $POST_BALANCE }")
    echo ""
    echo "      Post-deploy balance: $POST_BALANCE SOL (cost: $ACTUAL_COST SOL)"
    echo -e "${GREEN}      ✓ Deployment complete${NC}"
fi

# =============================================================================
# STEP 9: INITIALIZE & VERIFY
# =============================================================================
echo -e "${YELLOW}[9/9] Initializing config & verifying...${NC}"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}      Skipping init-config (dry run)${NC}"
else
    # Initialize config
    ANCHOR_PROVIDER_URL="$RPC_URL" \
    bun run scripts/init-config.ts

    echo -e "${GREEN}      ✓ Config initialized${NC}"
fi

# Verify program is on-chain
echo ""
echo "      Verifying program on-chain..."
PROGRAM_INFO=$(solana program show "$PROGRAM_ID" 2>/dev/null || echo "")
if echo "$PROGRAM_INFO" | grep -q "Program Id"; then
    echo -e "${GREEN}      ✓ Program verified on-chain${NC}"
    echo "$PROGRAM_INFO" | grep -E "Program Id|Data Length|Upgradeable" | while read -r line; do
        echo "        $line"
    done
else
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}      Program not yet on-chain (expected for dry run / new deployment)${NC}"
    else
        echo -e "${RED}      ✗ Could not verify program on-chain${NC}"
    fi
fi

# =============================================================================
# DONE
# =============================================================================
FINAL_BALANCE=$(solana balance "$WALLET_ADDRESS" 2>/dev/null | awk '{print $1}' || echo "unknown")

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
if [[ "$DRY_RUN" == true ]]; then
echo -e "${GREEN}║                    DRY RUN COMPLETE                            ║${NC}"
else
echo -e "${GREEN}║                    DEPLOYMENT COMPLETE                         ║${NC}"
fi
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "   Program ID: $PROGRAM_ID"
echo "   Network:    $NETWORK"
echo "   Balance:    $FINAL_BALANCE SOL"
echo ""

if [[ "$NETWORK" == "mainnet" && "$DRY_RUN" != true ]]; then
    echo -e "${YELLOW}IMPORTANT: Transfer upgrade authority to your Squads multisig:${NC}"
    echo ""
    echo "   solana program set-upgrade-authority $PROGRAM_ID \\"
    echo "     --new-upgrade-authority <YOUR_SQUADS_ADDRESS>"
    echo ""
    echo -e "${YELLOW}Then delete the keypair file from this computer.${NC}"
fi

echo "Verify: solana program show $PROGRAM_ID --url $NETWORK"
echo ""
