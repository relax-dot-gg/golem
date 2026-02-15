#!/usr/bin/env bash
set -euo pipefail

LEDGER_DIR="${LEDGER_DIR:-/ledger}"
LEDGER_REPO="${LEDGER_REPO:-}"

# Clone if not already present
if [ ! -d "${LEDGER_DIR}/.git" ]; then
    if [ -z "${LEDGER_REPO}" ]; then
        echo "ERROR: LEDGER_REPO not set and /ledger is empty. Set LEDGER_REPO or mount a pre-cloned repo."
        exit 1
    fi
    echo "Cloning ledger from ${LEDGER_REPO}..."
    git clone --no-checkout "${LEDGER_REPO}" "${LEDGER_DIR}"
fi

exec /opt/golem/golem.sh
