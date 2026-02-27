#!/usr/bin/env bash
# process-commands.sh — Reads a cmd YAML file, executes the command, writes output.
# Called by golem.sh for each pending command.
#
# Usage: process-commands.sh <cmd-file> <out-file>
#
# CMD YAML format:
#   command: "docker logs --tail 50 wordpress"
#   timeout: 30          # optional, default 30s
#   type: "shell"        # optional, default "shell". Future: "docker-api"
set -euo pipefail

CMD_FILE="$1"
OUT_FILE="$2"
DEFAULT_TIMEOUT=30

# --- Parse YAML (lightweight, no yq dependency) ---
# Extracts simple key: "value" or key: value fields
parse_yaml_field() {
    local file="$1" field="$2"
    grep -E "^${field}:" "${file}" 2>/dev/null | sed -E "s/^${field}:\s*//" | sed -E 's/^"(.*)"$/\1/' | sed -E "s/^'(.*)'$/\1/" | head -1 || true
}

command_str=$(parse_yaml_field "${CMD_FILE}" "command")
timeout_val=$(parse_yaml_field "${CMD_FILE}" "timeout")
cmd_type=$(parse_yaml_field "${CMD_FILE}" "type")

timeout_val="${timeout_val:-${DEFAULT_TIMEOUT}}"
cmd_type="${cmd_type:-shell}"

if [ -z "${command_str}" ]; then
    echo "ERROR: No 'command' field found in ${CMD_FILE}" > "${OUT_FILE}"
    exit 1
fi

# --- Header ---
{
    echo "# Output for: $(basename "${CMD_FILE}")"
    echo "# Executed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Host: $(hostname)"
    echo "# Command: ${command_str}"
    echo "# Timeout: ${timeout_val}s"
    echo "---"
} > "${OUT_FILE}"

# --- Signature Verification ---
if [ -n "${ALLOWED_SIGNERS_FILE:-}" ] && [ -f "${ALLOWED_SIGNERS_FILE}" ]; then
    sig_status=$(git log -1 --format="%G?" -- "${CMD_FILE}" 2>/dev/null || echo "U")
    if [ "${sig_status}" != "G" ]; then
        echo "ERROR: Command file '${CMD_FILE}' has invalid or missing signature (status: ${sig_status})." >> "${OUT_FILE}"
        echo "---" >> "${OUT_FILE}"
        echo "# EXIT: 126" >> "${OUT_FILE}"
        exit 0
    fi
fi

# --- Execute ---
case "${cmd_type}" in
    shell)
        # Execute with timeout, capture stdout+stderr, record exit code
        set +e
        output=$(timeout "${timeout_val}" bash -c "${command_str}" 2>&1)
        exit_code=$?
        set -e

        echo "${output}" >> "${OUT_FILE}"
        echo "---" >> "${OUT_FILE}"

        if [ "${exit_code}" -eq 124 ]; then
            echo "# EXIT: timeout (${timeout_val}s exceeded)" >> "${OUT_FILE}"
        else
            echo "# EXIT: ${exit_code}" >> "${OUT_FILE}"
        fi
        ;;

    docker-inspect)
        # Direct Docker API call via DOCKER_HOST (socket proxy)
        # command field contains the container name/id
        set +e
        output=$(curl -sf "http://${DOCKER_HOST:-docker-socket-proxy:2375}/containers/${command_str}/json" 2>&1)
        exit_code=$?
        set -e

        echo "${output}" >> "${OUT_FILE}"
        echo "---" >> "${OUT_FILE}"
        echo "# EXIT: ${exit_code}" >> "${OUT_FILE}"
        ;;

    docker-logs)
        # Fetch container logs via Docker API
        tail="${timeout_val}"  # reuse timeout as tail lines for logs
        set +e
        output=$(curl -sf "http://${DOCKER_HOST:-docker-socket-proxy:2375}/containers/${command_str}/logs?stdout=true&stderr=true&tail=${tail}" 2>&1)
        exit_code=$?
        set -e

        echo "${output}" >> "${OUT_FILE}"
        echo "---" >> "${OUT_FILE}"
        echo "# EXIT: ${exit_code}" >> "${OUT_FILE}"
        ;;

    *)
        echo "ERROR: Unknown command type '${cmd_type}'" >> "${OUT_FILE}"
        exit 1
        ;;
esac

exit 0
