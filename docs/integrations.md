# Coding app integrations

Choose an app in the sidebar and press **Sync**. A workspace row opens its folder in the focused pane; Command-click opens a new tab. The selected provider is saved across launches. Switching providers clears the previous list and discards any late response from that provider. A failed refresh retains the last successful list for the same provider and displays an error.

| App | Local source | Requirements and limits |
| --- | --- | --- |
| cmux | Existing cmux workspace socket adapter | Install cmux and permit socket access in its Automation settings. Password mode uses `CMUX_SOCKET_PASSWORD` inherited by mq-dir. |
| Orca | `orca worktree ps --limit 1000 --json` | Install the Orca CLI; lists up to 1,000 local, non-archived worktrees. Remote hosts are excluded. |
| Paseo | `paseo --host 127.0.0.1:6767 workspace ls --json` | Install its CLI and run the local daemon on port 6767. Custom ports and remote daemons are not supported yet. |
| Claude Code Desktop | Claude Desktop's local Code session metadata | Experimental adapter for `~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`. Create a local Code session in Claude Desktop first. This private format may change; CLI-only, cloud and SSH sessions are not imported. |
| Codex Desktop | Bundled Codex `app-server`, `thread/list` | Prefers Codex.app's bundled executable, falling back to a locally installed CLI. Reads the default `~/.codex` profile, including local CLI/editor/app-server sessions; it does not filter exclusively to Desktop-created sessions. Limited to 2,000 recent sessions. |

Duplicate folder paths collapse to one row. Missing local paths are disabled. **Open app** appears when the desktop application can be located; it launches the application, without resuming a particular session. Installing a CLI does not install its desktop app.

CLI discovery checks `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.bun/bin`, and `~/.npm-global/bin`. This feature does not install packages automatically. Process-backed adapters have bounded output and timeouts. Claude metadata files are limited to 8 MiB each; unreadable or malformed files report a sync error.

## Privacy and behavior

Sync imports workspace identifiers, titles and local folder paths for navigation. It does not submit prompts, resume agent turns, send messages, or modify workspace content. Provider responses/files may contain additional fields, but the adapter discards them rather than displaying conversation content. Sync results remain in memory; only the provider choice and normal mq-dir navigation state are persisted. The providers' own executable startup behavior remains controlled by those applications.

Codex requests are limited to initialization and paginated `thread/list` with `useStateDbOnly: true`; no thread-start or turn-start requests are sent. Custom Codex profiles are not currently configurable.

## Validation

Parser fixtures cover the four new providers; cmux retains its existing adapter. New tests also cover stale response rejection, folder deduplication, persisted selection, and Codex pagination/early process exit. Local smoke checks on the development Mac successfully retrieved Orca, Claude Desktop and Codex metadata. Paseo was not installed there, so its adapter has fixture validation only; live daemon compatibility remains to be checked.

References: [Paseo CLI](https://paseo.sh/docs/cli), [Paseo workspace list implementation](https://github.com/getpaseo/paseo/blob/main/packages/cli/src/commands/workspace/ls.ts), [Codex app-server](https://developers.openai.com/codex/app-server/), [Claude Desktop Code](https://code.claude.com/docs/en/desktop). Claude's metadata path is based on the installed app, not a documented public API contract.
