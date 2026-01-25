#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

PROGRAM_NAME=$(grep -A1 "\[programs.localnet\]" Anchor.toml | tail -1 | cut -d'=' -f1 | tr -d ' ')

solana-test-validator \
  --reset \
  --quiet \
  --bpf-program $(solana address -k "target/deploy/${PROGRAM_NAME}-keypair.json") \
    "target/deploy/${PROGRAM_NAME}.so"
