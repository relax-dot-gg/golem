# Golem

A headless, git-mediated command executor for infrastructure operations.

## What

Golem is a dumb bash loop that polls a git repo for commands, executes them, and commits the output. No LLM, no reasoning, no dependencies beyond bash and git.

The LLM (or human) writes commands to the repo. Golem runs them. Every command and output is a git commit — full audit trail for free.

## Why

- **No SSH quote escaping hell** — commands are YAML files, not nested shell strings
- **Audit trail built-in** — every operation is a git commit with author + timestamp
- **Zero edge cost** — no LLM on the target host, just bash polling
- **Git as transport** — no extra servers, webhooks, or message queues

## How It Works

```
LLM writes cmd.yaml ──> git push ──> golem polls (every 3s)
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

All hosts use the default branch (`main`). Host isolation is via directory paths.

### Directory Structure

Commands and outputs live under per-host incident directories:

```
hosts/
  <machine-uuid>/
    incidents/
      2026-02-15T16:30-disk-full/
        2026-02-15T16:30:00Z-cmd.yml
        2026-02-15T16:30:05Z-out.yml
        _report.yml
    archive/
      2026-02-15T16:30-disk-full/
        2026-02-15T16:30:00Z-cmd.yml
        2026-02-15T16:30:05Z-out.yml
        _report.yml
```

Archiving is a simple move of the incident directory from `incidents/` to `archive/`.

### Command Format

```yaml
command: "du -h --max-depth=2 / | sort -rh | head -20"
timeout: 30
type: shell
```

Supported types: `shell` (default), `docker-inspect`, `docker-logs`.

### Output Format

Outputs are YAML to include exit code and timing:

```yaml
exit_code: 0
started_at: 2026-02-15T16:30:05Z
ended_at: 2026-02-15T16:30:07Z
output: |-
  <raw stdout/stderr>
```

The final incident report is `_report.yml` in the incident directory.

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

# Place your deploy key (read-write access to ledger repo)
cp /path/to/deploy_key ./deploy_key
chmod 600 deploy_key

# Ensure /etc/machine-uuid exists
cat /etc/machine-uuid  # should output a UUID

# Start
LEDGER_REPO=git@github.com:org/ops-ledger.git docker compose up -d
```

## Host Access

Golem runs with full host access:
- Docker socket mounted for container operations
- Host filesystem mounted at `/host` for system-level ops
- Host network and PID namespace for full visibility

The safety layer is **who writes the commands** (your LLM, your triage pipeline, your approval process) — not the executor.

## Requirements

- Docker + Docker Compose
- `/etc/machine-uuid` on the host
- SSH deploy key with **write** access to the ledger repo
- Git repo (the "ledger") for command/output exchange

## Inspired By

[GITER](https://arxiv.org/abs/2511.04182) — Git-based spec/status exchange pattern for LLM-driven operations.

## License

MIT
