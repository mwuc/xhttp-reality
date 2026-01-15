# AGENTS.md
# Repository guidance for agentic coding assistants
# Scope: repository root (all files)

## Project overview
- This repo ships bash scripts that install/configure Xray with xhttp + Reality.
- Primary entry points: `xhttp-reality.sh` and `xhttp-reality_sidecar.sh`.
- Scripts assume Debian/Ubuntu, root access, and systemd.

## Repository layout
- `xhttp-reality.sh`: main installer/manager script (random/fixed identity).
- `xhttp-reality_sidecar.sh`: sidecar-aware variant with ownership marker.
- `xhttp-reality-zy.sh`: older/alternative installer (legacy).
- `readme.md`: usage docs and CLI parameters.

## Build, lint, and test commands
- Build: none (bash scripts, no compilation step).
- Lint (optional): if `shellcheck` is available, run:
  - `shellcheck xhttp-reality.sh`
  - `shellcheck xhttp-reality_sidecar.sh`
  - `shellcheck xhttp-reality-zy.sh`
- Formatting: no formatter configured. Keep existing layout.
- Tests: no automated tests in this repo.
- Single-test equivalent (manual smoke checks):
  - Version output: `bash xhttp-reality.sh version`
  - Status output: `bash xhttp-reality.sh -s`
  - Link output: `bash xhttp-reality.sh -l`
- Installation smoke test (requires root + dependencies + real VPS):
  - `bash xhttp-reality.sh -i -d example.com`
- Uninstall smoke test:
  - `bash xhttp-reality.sh -u`

## Runtime assumptions
- Targets Linux (Debian 10+/Ubuntu 20.04+), systemd-based.
- Scripts use `apt`, `curl`, `unzip`, `jq`, `uuid-runtime`, `openssl`.
- `xray` binary expected at `/usr/local/bin/xray` unless detected.
- Requires root (`id -u` check). Use `sudo` if needed.

## Code style guidelines (bash)
### General
- Use `#!/usr/bin/env bash` and `set -e` at top.
- Prefer `[[ ... ]]` for tests; avoid `[` when possible.
- Use `local` for function-scoped variables.
- Keep functions small and single-purpose.
- Avoid unnecessary subshells; prefer command substitution sparingly.
- Keep the existing Chinese/English log text style consistent.

### Imports and dependencies
- This repo does not use shell modules or `source` by default.
- If adding `source`, guard with file-existence checks.
- Prefer `command -v` for dependency checks.

### Naming conventions
- Constants and global config: `UPPER_SNAKE_CASE`.
- Regular globals: `UPPER_SNAKE_CASE` or descriptive `SNAKE_CASE`.
- Functions: `lower_snake_case` (e.g., `load_fixed_identity`).
- Temporary variables in functions: `lower_snake_case`.
- Avoid single-letter variables (except simple loop indices like `i`).

### Formatting
- Indent with two spaces.
- Keep long pipelines readable; wrap when needed.
- Use consistent section headers with `# ================= ... =================`.
- Keep heredoc blocks aligned and readable.

### Error handling
- Fail fast: return non-zero or `exit 1` on invalid state.
- Prefer explicit validation functions (see `validate_identity`).
- For external commands, log context before failure where useful.
- Allow `|| true` only when failure is expected and safe.
- Avoid silent failures; use `log` or `echo` for user-facing output.

### Logging
- Prefer `log` helper for consistent prefixing.
- Use clear success/failure markers (e.g., `✔`, `✘`) consistently.
- Keep logs single-line where possible.

### Security and safety
- Treat any config files under `/usr/local/etc/xray` as sensitive.
- Avoid printing private keys or secrets unless user explicitly requests.
- Validate user inputs (domain, UUIDs, paths) before writing config.
- Preserve existing safety checks around root access and services.

### Configuration and JSON
- Use `cat <<EOF` heredocs to write JSON.
- Keep JSON structure aligned with Xray expectations.
- Ensure string interpolation is quoted and validated.

### Systemd
- When editing unit files, reload daemon if service definition changes.
- Preserve `LimitNOFILE` and restart behavior unless needed.
- Keep service names consistent (`xray.service` by default).

### Filesystem
- Use `mkdir -p` before writing config directories.
- Avoid deleting directories unless explicitly requested.
- Prefer idempotent operations for install/uninstall flows.

## Compatibility notes
- Scripts are expected to run on VPS servers, not local dev machines.
- Network access is required for `curl` downloads during install.
- Some commands (`systemctl`, `ss`, `journalctl`) assume systemd.

## Cursor/Copilot rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.
- If added later, copy their rules into this file and follow them.

## Editing guidance for agents
- Keep changes minimal and scoped to user request.
- Avoid refactors that alter CLI flags or behavior unless asked.
- Maintain backwards compatibility with existing CLI parameters.
- Update `readme.md` only if user-facing behavior changes.
- Document any new flags or behavior in `readme.md`.

## Suggested workflow for changes
1. Identify the target script and related functions.
2. Update logic with minimal edits.
3. Run optional `shellcheck` if available.
4. Provide a short manual verification command.

## Reference commands (common)
- Install: `bash xhttp-reality.sh -i -d your.domain`
- Status: `bash xhttp-reality.sh -s`
- Link: `bash xhttp-reality.sh -l`
- Uninstall: `bash xhttp-reality.sh -u`
- Version: `bash xhttp-reality.sh version`

## Notes on legacy script
- `xhttp-reality-zy.sh` appears older; prefer editing main script unless asked.
- Ensure any fixes are mirrored only if user requests.
