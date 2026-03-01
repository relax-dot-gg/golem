# Golem

A headless, git-mediated command executor for infrastructure operations.

## What

Golem is a dumb bash loop that polls a git repo for commands, executes them, and commits the output. No LLM, no reasoning, no dependencies beyond bash and git.

The LLM (or human) writes commands to a dedicated Git branch for a specific host. Golem runs them. Every command and output is a git commit — full audit trail for free.

## Why

- **No SSH quote escaping hell** — commands are YAML files, not nested shell strings
- **Audit trail built-in** — every operation is a git commit with author + timestamp
- **Zero edge cost** — no LLM on the target host, just bash polling
- **Git as transport** — no extra servers, webhooks, or message queues
- **Host Isolation** — each host operates on its own Git branch (its UUID)

## How It Works

```
LLM writes cmd.yaml ──> git push (branch: <uuid>) ──> golem polls (every 5s)
                                                         │
                                                         ▼
                                                    executes command
                                                         │
                                                         ▼
                                              commits output ──> git push
                                                         │
                                                         ▼
                                              LLM reads output on next poll
```

### Branch Convention

Every host operates on its own Git branch named after its unique identity (typically the machine UUID from `/etc/machine-uuid`). This prevents cross-host state contamination and allows for independent operation.

### Directory Structure

Commands and outputs live under an incident directory:

```
incidents/
  2026-02-15-disk-full/
    001-cmd.yaml
    001-out.txt
    002-cmd.yaml
    002-out.txt
```

### Command Format

```yaml
command: "du -h --max-depth=2 / | sort -rh | head -20"
timeout: 30
```

### Output Format

The output file (`-out.txt`) contains the raw stdout/stderr of the command, wrapped in a header/footer for context and exit code.

## Security: Commit Signature Verification

Golem supports mandatory cryptographic signature verification of incoming commands. This ensures that even if your Git server is compromised, an attacker cannot execute commands on your hosts without possessing an authorized private key.

### How to Enable

1.  **Provision Keys:** On the target host, create `/etc/golem/allowed_signers`.
2.  **File Format:** This file follows the standard Git/SSH allowed signers format (see `man ssh-keygen`). Each line contains an email address and an SSH public key:
    ```
    admin@cyberstorm.dev ssh-ed25519 AAAAC3Nza...
    agent-planner@relax.gg ssh-rsa AAAAB3Nza...
    ```
3.  **Mount the File:** Update your `docker-compose.yml` to mount the signers file:
    ```yaml
    volumes:
      - /etc/golem/allowed_signers:/etc/golem/allowed_signers:ro
    ```

If the file is present, Golem will reject any command YAML that is not cryptographically signed (`Good` signature) by a key listed in the signers file.

## Deployment

```bash
# On the target host
mkdir -p /opt/golem
cd /opt/golem

# Start
LEDGER_URL=http://your-gitea:3000/org/ops-ledger.git \
GITEA_TOKEN=your-token \
NODE_NAME=optional-name \
docker compose up -d
```

## Host Access

Golem executes commands within an ephemeral `ubuntu:22.04` container that has full host access:
- Docker socket mounted for container operations
- Host filesystem mounted at `/host` for system-level ops (commands are executed via `chroot /host`)
- Host network and PID namespace for full visibility

The safety layer is **who writes the commands** (your LLM, your triage pipeline, your approval process) — enforced via **Commit Signature Verification**.

## Requirements

- Docker + Docker Compose
- `/etc/machine-uuid` on the host (or provided via `NODE_NAME`)
- Git repo (the "ledger") for command/output exchange

## Inspired By

[GITER](https://arxiv.org/abs/2511.04182) — Git-based spec/status exchange pattern for LLM-driven operations.
