#!/bin/bash
set -e

# =============================================================================
# PRE-DEPLOYMENT SAFETY CHECK
# =============================================================================
# Usage:
#   ./scripts/pre-deploy-check.sh devnet
#   ./scripts/pre-deploy-check.sh mainnet
#
# Environment:
#   RPC_URL  - Override default RPC endpoint
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NETWORK="${1:-devnet}"
ERRORS=0
WARNINGS=0

echo ""
echo "=============================================="
echo "  PRE-DEPLOYMENT SAFETY CHECK"
echo "  Network: $NETWORK"
echo "=============================================="
echo ""

check_pass() { echo -e "${GREEN}✓${NC} $1"; }
check_fail() { echo -e "${RED}✗ ERROR:${NC} $1"; ERRORS=$((ERRORS + 1)); }
check_warn() { echo -e "${YELLOW}⚠ WARNING:${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

PROGRAM_NAME=$(grep -A1 "\[programs.localnet\]" Anchor.toml | tail -1 | cut -d'=' -f1 | tr -d ' ')

# -----------------------------------------------------------------------------
# 1. NETWORK
# -----------------------------------------------------------------------------
echo "1. NETWORK"
echo "   -------"

if [[ "$NETWORK" != "devnet" && "$NETWORK" != "mainnet" ]]; then
    check_fail "Invalid network '$NETWORK'. Use 'devnet' or 'mainnet'"
    exit 1
fi

if [[ -n "$RPC_URL" ]]; then
    check_pass "Using RPC override: $RPC_URL"
elif [[ "$NETWORK" == "mainnet" ]]; then
    RPC_URL="https://api.mainnet-beta.solana.com"
    MIN_SOL=10
else
    RPC_URL="https://api.devnet.solana.com"
    MIN_SOL=8
fi

CURRENT_RPC=$(solana config get | grep "RPC URL" | awk '{print $3}')
if [[ "$CURRENT_RPC" == *"$NETWORK"* ]] || [[ "$NETWORK" == "devnet" && "$CURRENT_RPC" == *"devnet"* ]] || [[ "$NETWORK" == "mainnet" && "$CURRENT_RPC" == *"mainnet"* ]]; then
    check_pass "Solana CLI configured for $NETWORK"
else
    check_fail "Run: solana config set --url $RPC_URL"
fi

# -----------------------------------------------------------------------------
# 2. WALLET
# -----------------------------------------------------------------------------
echo ""
echo "2. WALLET"
echo "   ------"

BALANCE=$(solana balance 2>/dev/null | awk '{print $1}' || echo "0")
BALANCE_INT=${BALANCE%.*}
if [[ "$BALANCE_INT" -ge "$MIN_SOL" ]]; then
    check_pass "Balance: $BALANCE SOL (need $MIN_SOL)"
else
    check_fail "Insufficient: $BALANCE SOL (need $MIN_SOL)"
fi

# Mainnet: Warn if using default keypair
if [[ "$NETWORK" == "mainnet" ]]; then
    WALLET_PATH=$(solana config get | grep "Keypair Path" | awk '{print $3}')
    if [[ "$WALLET_PATH" == *"id.json"* ]]; then
        check_warn "Using default keypair for mainnet deployment"
    fi
fi

# -----------------------------------------------------------------------------
# 3. PROGRAM ID
# -----------------------------------------------------------------------------
echo ""
echo "3. PROGRAM ID"
echo "   ----------"

KEYPAIR_PATH="target/deploy/${PROGRAM_NAME}-keypair.json"
if [[ -f "$KEYPAIR_PATH" ]]; then
    KEYPAIR_ID=$(solana address -k "$KEYPAIR_PATH")
    check_pass "Keypair: $KEYPAIR_ID"
else
    check_fail "No keypair at $KEYPAIR_PATH (run with --new)"
fi

LIB_ID=$(grep "declare_id!" "programs/${PROGRAM_NAME}/src/lib.rs" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || echo "NOT_FOUND")
ANCHOR_ID=$(grep -A1 "\[programs.$NETWORK\]" Anchor.toml 2>/dev/null | grep "$PROGRAM_NAME" | sed 's/.*"\(.*\)".*/\1/' || echo "NOT_FOUND")

if [[ -f "$KEYPAIR_PATH" && "$KEYPAIR_ID" == "$LIB_ID" && "$LIB_ID" == "$ANCHOR_ID" ]]; then
    check_pass "All IDs match"
else
    check_fail "ID mismatch - Keypair: $KEYPAIR_ID, lib.rs: $LIB_ID, Anchor.toml: $ANCHOR_ID"
fi

# -----------------------------------------------------------------------------
# 4. BUILD
# -----------------------------------------------------------------------------
echo ""
echo "4. BUILD"
echo "   -----"

if [[ -f "target/deploy/${PROGRAM_NAME}.so" ]]; then
    check_pass "Program binary exists"
else
    check_fail "Run: anchor build"
fi

# -----------------------------------------------------------------------------
# 5. ORPHANED BUFFER CHECK
# -----------------------------------------------------------------------------
echo ""
echo "5. ORPHANED BUFFERS"
echo "   ----------------"

BUFFER_OUTPUT=$(solana program show --buffers 2>/dev/null || echo "")
BUFFER_COUNT=$(echo "$BUFFER_OUTPUT" | grep -cE "^[A-HJ-NP-Za-km-z1-9]{32,}" || true)

if [[ "$BUFFER_COUNT" -gt 0 ]]; then
    check_warn "Found $BUFFER_COUNT orphaned buffer(s) consuming SOL"
    echo "        Recover: solana program close --buffers"
else
    check_pass "No orphaned buffers"
fi

# -----------------------------------------------------------------------------
# 6. MAINNET-SPECIFIC CHECKS
# -----------------------------------------------------------------------------
if [[ "$NETWORK" == "mainnet" ]]; then
    echo ""
    echo "6. MAINNET SAFETY"
    echo "   --------------"

    # Check for placeholder program ID
    if [[ "$ANCHOR_ID" == "11111111111111111111111111111111" ]]; then
        check_fail "Program ID is still placeholder in Anchor.toml"
    fi

    # Check for mainnet keypair
    MAINNET_KEYPAIR="target/deploy/${PROGRAM_NAME}_mainnet-keypair.json"
    if [[ ! -f "$MAINNET_KEYPAIR" ]]; then
        check_fail "Mainnet keypair not found: $MAINNET_KEYPAIR"
    else
        MAINNET_ID=$(solana address -k "$MAINNET_KEYPAIR" 2>/dev/null || echo "ERROR")
        if [[ "$MAINNET_ID" != "ERROR" ]]; then
            check_pass "Mainnet keypair: $MAINNET_ID"
        fi
    fi

    # Check for TREASURY_ADDRESS
    if [[ -z "$TREASURY_ADDRESS" ]]; then
        check_warn "TREASURY_ADDRESS not set (required for mainnet init-config)"
    else
        check_pass "TREASURY_ADDRESS set: $TREASURY_ADDRESS"
    fi

    # Check devnet/mainnet ID collision
    DEVNET_ID=$(grep -A1 "\[programs.devnet\]" Anchor.toml 2>/dev/null | grep "$PROGRAM_NAME" | sed 's/.*"\(.*\)".*/\1/' || echo "")
    if [[ -n "$DEVNET_ID" && "$ANCHOR_ID" == "$DEVNET_ID" ]]; then
        check_fail "Mainnet and devnet program IDs are the same!"
    fi
fi

# -----------------------------------------------------------------------------
# 7. SUMMARY
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  SUMMARY"
echo "=============================================="
echo ""

if [[ "$ERRORS" -gt 0 ]]; then
    echo -e "${RED}FAILED: $ERRORS error(s)${NC}"
    if [[ "$WARNINGS" -gt 0 ]]; then
        echo -e "${YELLOW}  Plus $WARNINGS warning(s)${NC}"
    fi
    echo ""
    echo "  DO NOT DEPLOY - fix errors above first!"
    exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
    echo -e "${YELLOW}PASSED WITH WARNINGS: $WARNINGS warning(s)${NC}"
    echo ""
    echo "  Review warnings above before deploying."
    exit 0
else
    echo -e "${GREEN}ALL CHECKS PASSED${NC}"
    echo ""
    echo "  Ready: ./scripts/deploy.sh $NETWORK"
fi
echo ""
