# Safety Audit for GUI Automation (symoperate)

This document outlines the safety architecture and guarantees provided by `symoperate`, a native macOS desktop automation server. Because `symoperate` can drive the user's desktop, stringent safety guards are in place.

## Core Guarantees

### Supervised, Local Operation
- **Stdio-Only Transport**: `symoperate` operates entirely over standard input/output (JSON-RPC) as an MCP server.
- **No Remote Daemon**: There is no listening daemon, no network socket, and no background service. The host agent (e.g., Claude Desktop, Cursor) starts the process, issues a single bounded action, and receives the result.
- **One Action at a Time**: `symoperate` does not accept bulk automation scripts or run loops itself; the agent must evaluate the screen state between each action.

### Destructive-Action Guards
`symoperate` explicitly refuses to interact with UI elements whose role or label implies a destructive or high-privilege action.
By default, element-based actions (like `click`) are blocked if the target matches any of the following keywords (case-insensitive):
- `delete`, `remove`, `erase`, `clear`, `trash`, `uninstall`
- `allow`, `authorize`, `unlock`
- `quit`, `terminate`, `force quit`, `shutdown`

*Note: These guards can be augmented with `ActionPolicy`, but they cannot be disabled.*

### Secure Text Field Blocking
- `symoperate` will completely refuse to target or type into elements with the `AXSecureTextField` role. 
- You cannot click on a password field using `snapshot_id` + `element_id`, nor can you type text into a focused secure field.

## Permission Boundaries

Agents using `symoperate` must not automate the following flows without explicit user confirmation:
- Passwords and account recovery.
- Payment flows.
- macOS system permission dialogs (e.g., granting Accessibility, Screen Recording, or Full Disk Access).

The destructive-action guard naturally blocks buttons like "Allow" or "Authorize" in permission dialogs to prevent agents from self-escalating their host's privileges.

### Responsible-Process Attribution

On macOS, TCC permissions (Accessibility, Screen Recording) are granted per
*process*, not per user or per binary. Whether `AXIsProcessTrusted()` or
`CGPreflightScreenCaptureAccess()` returns `true` depends entirely on which
process calls them.

`PermissionSnapshot` now includes a `source` block that identifies the process
whose grants the booleans describe:

| Field | Description |
|---|---|
| `pid` | The process ID that called the TCC APIs. |
| `ppid` | The parent process ID that launched symoperate. |
| `executablePath` | Resolved absolute path of the running binary. |
| `launchingProcessName` | Human-readable name of the parent process (e.g. "Terminal", "zsh", "Cursor"). |
| `note` | Plain-English explanation of the per-process nature of the grants. |

This attribution is surfaced in `symoperate doctor`, the `permissions_status`
MCP tool, and any other consumer of `PermissionSnapshot`.

**Why this matters:** When a user runs `symoperate doctor` from a terminal, the
booleans reflect what the terminal process (or `zsh`) is allowed to do, not what
the MCP host process (e.g. Cursor, Claude Desktop) would be allowed to do.
Granting Accessibility to `Terminal.app` does not grant it to `Cursor.app`.
The `source` block makes this distinction visible and auditable.

To grant permissions correctly, the user should add their MCP host application
in **System Settings → Privacy & Security → Accessibility** and **Screen
Recording**, then launch `symoperate` via that host's MCP configuration, not
from a terminal.

## Operation History

To ensure an auditable trail, `symoperate` maintains a local history of all GUI automation actions.

- **Location**: `~/.local/share/symoperate/history.jsonl`
- **Content**: Records the action type, targets (where safe), result message, and refusal reasons.
- **Privacy Guarantee**: `symoperate` does not persist sensitive typed text. For the `type_text` command, the text is redacted (e.g., `<redacted: 12 chars>`) in the history logs to prevent accidental storage of secrets or PII.
- **Verification**: You can view the history by running `symoperate history --json`.
