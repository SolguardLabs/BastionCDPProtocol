#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

forge fmt --check
forge build --deny warnings
FOUNDRY_PROFILE=ci forge test --deny warnings
