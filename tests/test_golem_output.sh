#!/usr/bin/env bash
set -e

# Setup a clean test environment
TEST_DIR=$(mktemp -d)
echo "Testing Golem output format in $TEST_DIR"
cd "$TEST_DIR"

# Mock Git (simulate a ledger clone)
cat << 'MOCK' > git
#!/usr/bin/env bash
# Mock git clone, push, commit, etc.
if [[ "$1" == "clone" ]]; then
    mkdir -p "$3"
    cd "$3"
    mkdir -p incidents/test-incident
    cat << 'CMD' > incidents/test-incident/001-cmd.yaml
command: "echo 'hello from golem'"
timeout: 30
CMD
    exit 0
fi
exit 0
MOCK
chmod +x git

# Mock Docker (simulate command execution)
cat << 'MOCK' > docker
#!/usr/bin/env bash
# Simply print the hello message to simulate stdout
echo "hello from golem"
MOCK
chmod +x docker

export PATH="$TEST_DIR:$PATH"
export RUN_ONCE=1
export MACHINE_UUID_FILE="$TEST_DIR/machine-uuid"
echo "test-host-uuid" > "$MACHINE_UUID_FILE"

# Run golem (passing current dir as "ledger url" to be used by clone)
/Users/allenday/src/tmp/golem/golem.sh "$TEST_DIR" "test-host-uuid" > /dev/null 2>&1

# Verify output file existence
LEDGER_DIR="/tmp/golem-ledger"
OUT_FILE="$LEDGER_DIR/incidents/test-incident/001-out.txt"

if [[ ! -f "$OUT_FILE" ]]; then
    echo "FAIL: Output file $OUT_FILE not created"
    exit 1
fi

# Verify YAML structure
echo "Checking output YAML structure..."
cat "$OUT_FILE"

# 1. Check exit_code
if grep -q "^exit_code: 0" "$OUT_FILE"; then
    echo "✅ Found exit_code"
else
    echo "❌ Missing or invalid exit_code"
    exit 1
fi

# 2. Check timestamps
if grep -q "^started_at: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z" "$OUT_FILE" && \
   grep -q "^ended_at: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z" "$OUT_FILE"; then
    echo "✅ Found valid ISO8601 timestamps"
else
    echo "❌ Missing or malformed timestamps"
    exit 1
fi

# 3. Check output block and indentation
if grep -q "^output: |-" "$OUT_FILE" && grep -q "  hello from golem" "$OUT_FILE"; then
    echo "✅ Found indented output block"
else
    echo "❌ Missing or incorrectly formatted output block"
    exit 1
fi

echo "SUCCESS: Golem output format verified"
