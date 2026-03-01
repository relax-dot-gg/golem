#!/usr/bin/env bash
set -eo pipefail

# Golem: Git-mediated bash executor (Production Parity)
# Matches the UUID-branching and incidents/ directory protocol

LEDGER_URL=$1
NODE_NAME=$2
POLL_INTERVAL=${POLL_INTERVAL:-5}
RUN_ONCE=${RUN_ONCE:-0} # For testing
ALLOWED_SIGNERS_FILE=${ALLOWED_SIGNERS_FILE:-/etc/golem/allowed_signers}
MACHINE_UUID_FILE="${MACHINE_UUID_FILE:-/etc/machine-uuid}"

if [[ -z "$LEDGER_URL" ]]; then
    echo "Usage: $0 <ledger_url> [node_name]"
    exit 1
fi

# Identity: Use machine UUID if available, else fallback to node_name or hostname
if [[ -f "$MACHINE_UUID_FILE" ]]; then
    MACHINE_UUID=$(cat "$MACHINE_UUID_FILE" | tr -d '[:space:]')
elif [[ -n "$NODE_NAME" ]]; then
    MACHINE_UUID="$NODE_NAME"
else
    MACHINE_UUID=$(hostname)
fi

# In production, every host has its own branch matching its UUID
GIT_BRANCH="${MACHINE_UUID}"
WORKDIR="/tmp/golem-ledger"

if [[ -n "$GITEA_TOKEN" ]]; then
    git config --global http.extraHeader "AUTHORIZATION: token $GITEA_TOKEN"
fi

# Ensure git identity is set
if ! git config --global user.email >/dev/null; then
    git config --global user.email "golem@cyberstorm.dev"
    git config --global user.name "Golem Executor"
fi

# Configure signature verification if configured
if [[ -f "$ALLOWED_SIGNERS_FILE" ]]; then
    git config --global gpg.format ssh
    git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS_FILE"
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
echo "🤖 Golem started on node: $MACHINE_UUID (Branch: $GIT_BRANCH)"

# Sync branch
if git ls-remote --heads "$LEDGER_URL" "$GIT_BRANCH" | grep -q "$GIT_BRANCH"; then
    git clone --branch "$GIT_BRANCH" "$LEDGER_URL" "$WORKDIR"
else
    # First time initialization for this host
    git clone "$LEDGER_URL" "$WORKDIR"
    cd "$WORKDIR"
    git checkout --orphan "$GIT_BRANCH"
    git rm -rf . || true
    echo "# Golem ledger for $MACHINE_UUID" > README.md
    git add README.md
    git commit -m "golem: init branch for $MACHINE_UUID"
    git push origin "$GIT_BRANCH"
fi

cd "$WORKDIR"

process_commands() {
    # Match official structure: incidents/<timestamp>-<slug>/<NNN>-cmd.yaml
    mkdir -p incidents
    
    # Find all cmd files recursively in incidents/
    PENDING_CMDS=$(find incidents -name "*-cmd.yaml" | sort)
    
    for CMD_FILE in $PENDING_CMDS; do
        OUT_FILE="${CMD_FILE%-cmd.yaml}-out.txt"
        
        if [[ ! -f "$OUT_FILE" ]]; then
            echo "⚡ Executing command from $CMD_FILE..."
            
            # Simple YAML parser (extract 'command' field)
            CMD=$(grep "^command:" "$CMD_FILE" | head -1 | cut -d: -f2- | sed -e 's/^[[:space:]]*//' -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//') || true
            TIMEOUT=$(grep "^timeout:" "$CMD_FILE" | head -1 | cut -d: -f2- | sed -e 's/^[[:space:]]*//' -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//') || true
            TIMEOUT="${TIMEOUT:-30}"
            
            echo "--- COMMAND START ---" > "$OUT_FILE"
            echo "$CMD" >> "$OUT_FILE"
            echo "--- OUTPUT START ---" >> "$OUT_FILE"
            
            # Check signature if we are enforcing it
            IS_ALLOWED=1
            if [[ -f "$ALLOWED_SIGNERS_FILE" ]]; then
                SIG_STATUS=$(git log -1 --format="%G?" -- "$CMD_FILE" 2>/dev/null || echo "U")
                if [[ "$SIG_STATUS" != "G" ]]; then
                    IS_ALLOWED=0
                    echo "❌ ERROR: Command file '$CMD_FILE' has invalid or missing signature (status: $SIG_STATUS)." >> "$OUT_FILE"
                fi
            fi
            
            if [[ "$IS_ALLOWED" -eq 0 ]]; then
                EXIT_CODE=126
            else
                # Execute in an ephemeral container with host access (replaces SSH exec)
                set +e
                docker run --rm \
                    --name "golem-task-$(date +%s)" \
                    --pid=host \
                    --network=host \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v /:/host:rw \
                    ubuntu:22.04 timeout "$TIMEOUT" sh -c "chroot /host bash -c '$CMD'" >> "$OUT_FILE" 2>&1
                EXIT_CODE=$?
                set -e
            fi
            
            echo "--- STATUS: $EXIT_CODE ---" >> "$OUT_FILE"
            
            # Commit results back to ledger
            git add "$OUT_FILE"
            git commit -m "golem($MACHINE_UUID): output for $(basename "$CMD_FILE")" || true
            git push origin "$GIT_BRANCH" || true
            
            echo "✅ Finished $CMD_FILE"
        fi
    done
}

while true; do
    git fetch origin "$GIT_BRANCH" || true
    git reset --hard "origin/$GIT_BRANCH" || true

    process_commands

    if [[ "$RUN_ONCE" -eq 1 ]]; then
        break
    fi

    sleep "$POLL_INTERVAL"
done
