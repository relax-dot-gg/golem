#!/usr/bin/env bash
# golem.sh — Headless executor that polls a git ledger for pending commands.
# No LLM, no reasoning. Just fetch → find pending → execute → commit → push.
set -euo pipefail

# --- Configuration ---
LEDGER_DIR="${LEDGER_DIR:-/ledger}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"
GIT_REMOTE="${GIT_REMOTE:-origin}"
PROCESS_SCRIPT="${PROCESS_SCRIPT:-/opt/golem/process-commands.sh}"

# Identity: read machine UUID from /etc/machine-uuid (injected via volume mount)
MACHINE_UUID_FILE="${MACHINE_UUID_FILE:-/etc/machine-uuid}"
export ALLOWED_SIGNERS_FILE="${ALLOWED_SIGNERS_FILE:-/etc/golem/allowed_signers}"

if [ ! -f "${MACHINE_UUID_FILE}" ]; then
    echo "FATAL: ${MACHINE_UUID_FILE} not found. Mount the host's /etc/machine-uuid into the container." >&2
    exit 1
fi
MACHINE_UUID=$(cat "${MACHINE_UUID_FILE}" | tr -d '[:space:]')
if [ -z "${MACHINE_UUID}" ]; then
    echo "FATAL: ${MACHINE_UUID_FILE} is empty." >&2
    exit 1
fi

# Branch = machine UUID
GIT_BRANCH="${MACHINE_UUID}"
INCIDENTS_DIR="${LEDGER_DIR}/incidents"

# --- Logging ---
log() { echo "[golem $(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# --- Setup ---
if [ ! -d "${LEDGER_DIR}/.git" ]; then
    log "ERROR: ${LEDGER_DIR} is not a git repository. Clone the ledger first."
    exit 1
fi

cd "${LEDGER_DIR}"

# Configure git identity for commits
git config user.name "${GIT_USER_NAME:-golem-${MACHINE_UUID}}"
git config user.email "${GIT_USER_EMAIL:-golem@noreply}"

if [ -f "${ALLOWED_SIGNERS_FILE}" ]; then
    git config gpg.format ssh
    git config gpg.ssh.allowedSignersFile "${ALLOWED_SIGNERS_FILE}"
fi

# Ensure our branch exists (create from remote if available, or orphan)
if git ls-remote --heads "${GIT_REMOTE}" "${GIT_BRANCH}" | grep -q "${GIT_BRANCH}"; then
    git fetch "${GIT_REMOTE}" "${GIT_BRANCH}" --quiet
    git checkout -B "${GIT_BRANCH}" "${GIT_REMOTE}/${GIT_BRANCH}" --quiet
else
    git checkout --orphan "${GIT_BRANCH}" --quiet 2>/dev/null || git checkout "${GIT_BRANCH}" --quiet
    git rm -rf . --quiet 2>/dev/null || true
    echo "# Golem ledger for ${MACHINE_UUID}" > README.md
    git add README.md
    git commit -m "golem: init branch for ${MACHINE_UUID}" --quiet
    git push "${GIT_REMOTE}" "${GIT_BRANCH}" --quiet 2>/dev/null || true
fi

log "Golem started uuid=${MACHINE_UUID}, branch=${GIT_BRANCH}, polling every ${POLL_INTERVAL}s"
log "Watching: ${INCIDENTS_DIR}"

# --- Main Loop ---
while true; do
    # Fetch latest from remote
    if ! git fetch "${GIT_REMOTE}" "${GIT_BRANCH}" --quiet 2>/dev/null; then
        log "WARN: git fetch failed, retrying in ${POLL_INTERVAL}s"
        sleep "${POLL_INTERVAL}"
        continue
    fi

    # Fast-forward merge (no conflicts in a well-behaved ledger)
    git merge "${GIT_REMOTE}/${GIT_BRANCH}" --ff-only --quiet 2>/dev/null || true

    # Ensure incidents directory exists
    mkdir -p "${INCIDENTS_DIR}"

    # Find all pending cmd files (cmd exists but no corresponding out file)
    pending_found=false
    for incident_dir in "${INCIDENTS_DIR}"/*/; do
        [ -d "${incident_dir}" ] || continue

        for cmd_file in "${incident_dir}"/*-cmd.yaml; do
            [ -f "${cmd_file}" ] || continue

            # Derive output filename: TIMESTAMP-cmd.yaml → TIMESTAMP-out.txt
            base=$(basename "${cmd_file}")
            ts_prefix="${base%%-cmd.yaml}"
            out_file="${incident_dir}/${ts_prefix}-out.txt"

            # Skip if already processed
            [ -f "${out_file}" ] && continue

            pending_found=true
            log "Processing: ${cmd_file}"

            # Execute via process-commands.sh
            if bash "${PROCESS_SCRIPT}" "${cmd_file}" "${out_file}"; then
                log "OK: ${out_file}"
            else
                log "WARN: Non-zero exit from processor for ${cmd_file}"
            fi

            # Commit and push the output
            cd "${LEDGER_DIR}"
            if [ -f "${out_file}" ]; then
                git add "${out_file}"
                git commit -m "golem(${MACHINE_UUID:0:8}): output for ${base}" --quiet
                if ! git push "${GIT_REMOTE}" "${GIT_BRANCH}" --quiet 2>/dev/null; then
                    log "WARN: push failed, will retry next cycle"
                fi
            else
                log "WARN: output file not created for ${cmd_file}, skipping commit"
                # Create a minimal error output so we don't loop on this cmd forever
                echo "ERROR: process-commands.sh failed to create output" > "${out_file}"
                git add "${out_file}"
                git commit -m "golem(${MACHINE_UUID:0:8}): ERROR for ${base}" --quiet
                git push "${GIT_REMOTE}" "${GIT_BRANCH}" --quiet 2>/dev/null || true
            fi
        done
    done

    if [ "${pending_found}" = false ]; then
        : # Nothing pending — silent poll
    fi

    sleep "${POLL_INTERVAL}"
done
