#!/bin/bash
set -e

# =============================================================================
# PRE-DEPLOYMENT SAFETY CHECK
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NETWORK="${1:-devnet}"
ERRORS=0

echo ""
echo "=============================================="
echo "  PRE-DEPLOYMENT SAFETY CHECK"
echo "  Network: $NETWORK"
echo "=============================================="
echo ""

check_pass() { echo -e "${GREEN}✓${NC} $1"; }
check_fail() { echo -e "${RED}✗ ERROR:${NC} $1"; ERRORS=$((ERRORS + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

PROGRAM_NAME=$(grep -A1 "\[programs.localnet\]" Anchor.toml | tail -1 | cut -d'=' -f1 | tr -d ' ')

# Network
echo "1. NETWORK"
if [[ "$NETWORK" == "mainnet" ]]; then
    RPC_URL="https://api.mainnet-beta.solana.com"
    MIN_SOL=8
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

# Wallet
echo ""
echo "2. WALLET"
BALANCE=$(solana balance 2>/dev/null | awk '{print $1}' || echo "0")
BALANCE_INT=${BALANCE%.*}
if [[ "$BALANCE_INT" -ge "$MIN_SOL" ]]; then
    check_pass "Balance: $BALANCE SOL (need $MIN_SOL)"
else
    check_fail "Insufficient: $BALANCE SOL (need $MIN_SOL)"
fi

# Program ID
echo ""
echo "3. PROGRAM ID"
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

# Build
echo ""
echo "4. BUILD"
if [[ -f "target/deploy/${PROGRAM_NAME}.so" ]]; then
    check_pass "Program binary exists"
else
    check_fail "Run: anchor build"
fi

# Summary
echo ""
echo "=============================================="
if [[ "$ERRORS" -gt 0 ]]; then
    echo -e "${RED}FAILED: $ERRORS error(s) - DO NOT DEPLOY${NC}"
    exit 1
else
    echo -e "${GREEN}ALL CHECKS PASSED${NC}"
fi
echo ""
