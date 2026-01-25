#!/bin/bash
set -e

# =============================================================================
# SOLANA DEPLOY SCRIPT
# =============================================================================
# Usage:
#   ./scripts/deploy.sh devnet        # Upgrade existing devnet deployment
#   ./scripts/deploy.sh devnet --new  # New devnet deployment (new program ID)
#   ./scripts/deploy.sh mainnet       # Mainnet deployment
#
# Environment:
#   TREASURY_ADDRESS  - Required for mainnet (Squads multisig address)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NETWORK="${1:-devnet}"
NEW_DEPLOYMENT=false

for arg in "$@"; do
    case $arg in
        --new)
            NEW_DEPLOYMENT=true
            shift
            ;;
    esac
done

if [[ "$NETWORK" != "devnet" && "$NETWORK" != "mainnet" ]]; then
    echo -e "${RED}Usage: $0 <devnet|mainnet> [--new]${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Get program name from Anchor.toml
PROGRAM_NAME=$(grep -A1 "\[programs.localnet\]" Anchor.toml | tail -1 | cut -d'=' -f1 | tr -d ' ')

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    SOLANA DEPLOYMENT                           ║${NC}"
echo -e "${BLUE}║                    Network: ${NETWORK}                               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# STEP 1: CONFIGURE NETWORK
# =============================================================================
echo -e "${YELLOW}[1/6] Configuring network...${NC}"

if [[ "$NETWORK" == "mainnet" ]]; then
    RPC_URL="https://api.mainnet-beta.solana.com"
else
    RPC_URL="https://api.devnet.solana.com"
fi

solana config set --url "$RPC_URL" > /dev/null
echo -e "${GREEN}      ✓ Set to $NETWORK${NC}"

# =============================================================================
# STEP 2: WALLET INFO
# =============================================================================
echo -e "${YELLOW}[2/6] Checking wallet...${NC}"

WALLET_ADDRESS=$(solana address)
BALANCE=$(solana balance | awk '{print $1}')

echo "      Wallet: $WALLET_ADDRESS"
echo "      Balance: $BALANCE SOL"
echo -e "${GREEN}      ✓ Wallet OK${NC}"

# =============================================================================
# STEP 3: MAINNET SAFETY CHECKS
# =============================================================================
if [[ "$NETWORK" == "mainnet" ]]; then
    echo -e "${YELLOW}[3/6] Mainnet safety checks...${NC}"

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
    echo -e "${YELLOW}[3/6] Safety checks...${NC}"
    echo -e "${GREEN}      ✓ Devnet deployment${NC}"
fi

# =============================================================================
# STEP 4: SETUP PROGRAM ID
# =============================================================================
echo -e "${YELLOW}[4/6] Program ID setup...${NC}"

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
echo -e "${YELLOW}[5/6] Building program...${NC}"

if [[ "$NETWORK" == "mainnet" ]]; then
    anchor build --verifiable 2>&1 | tail -3
else
    anchor build 2>&1 | tail -3
fi
echo -e "${GREEN}      ✓ Build complete${NC}"

# =============================================================================
# STEP 6: DEPLOY
# =============================================================================
echo -e "${YELLOW}[6/6] Deploying to $NETWORK...${NC}"

PROGRAM_EXISTS=$(solana program show "$PROGRAM_ID" 2>/dev/null | grep -c "Program Id" || echo "0")

# Balance check
BALANCE=$(solana balance | awk '{print $1}')
BALANCE_INT=${BALANCE%.*}

if [[ "$PROGRAM_EXISTS" == "0" || "$NEW_DEPLOYMENT" == true ]]; then
    REQUIRED_SOL=8
else
    REQUIRED_SOL=1
fi

if [[ "$BALANCE_INT" -lt "$REQUIRED_SOL" ]]; then
    echo -e "${RED}      ✗ Insufficient balance. Need $REQUIRED_SOL SOL (have $BALANCE SOL).${NC}"
    if [[ "$NETWORK" == "devnet" ]]; then
        echo "      Run: solana airdrop 2  (repeat as needed)"
    fi
    exit 1
fi

if [[ "$PROGRAM_EXISTS" == "0" || "$NEW_DEPLOYMENT" == true ]]; then
    echo "      First-time deployment..."
    if [[ "$NETWORK" == "mainnet" ]]; then
        anchor deploy --provider.cluster mainnet --program-keypair "$KEYPAIR_PATH"
    else
        anchor deploy --provider.cluster devnet
    fi
else
    echo "      Upgrading existing program..."
    anchor upgrade target/deploy/${PROGRAM_NAME}.so \
        --program-id "$PROGRAM_ID" \
        --provider.cluster "$NETWORK"
fi

echo -e "${GREEN}      ✓ Deployment complete${NC}"

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    DEPLOYMENT COMPLETE                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "   Program ID: $PROGRAM_ID"
echo "   Network:    $NETWORK"
echo ""

if [[ "$NETWORK" == "mainnet" ]]; then
    echo -e "${YELLOW}IMPORTANT: Transfer upgrade authority to your Squads multisig:${NC}"
    echo ""
    echo "   solana program set-upgrade-authority $PROGRAM_ID \\"
    echo "     --new-upgrade-authority <YOUR_SQUADS_ADDRESS>"
    echo ""
    echo -e "${YELLOW}Then delete the keypair file from this computer.${NC}"
fi

echo "Verify: solana program show $PROGRAM_ID --url $NETWORK"
echo ""
