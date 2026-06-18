# symaira-operate

> Let an AI agent see and drive your Mac — locally, over MCP.

`symoperate` is a native macOS desktop-automation **MCP server**. It exposes
screenshots, the Accessibility tree, mouse/keyboard input, and app/window control
over stdio, so an agent (Claude Desktop, OpenCode, Cursor, …) can operate the
GUI: open an app, find a button, click it, type, save. It is a supervised, local
tool — not a remote-control daemon.

Part of the [Symaira](../ECOSYSTEM.md) family, and the agent-native sibling of
[`symaira-tune`](../symaira-tune) (hardware tuning): **operate = GUI actions,
tune = thermals/brightness/power.**

> **Status: v0.1.** Working native implementation (rebranded from the author's
> `mac-operator` prototype), 29 tests passing. Not released/notarized yet.

## Requirements

- macOS 15+
- `Accessibility` and `Screen Recording` permissions for the host process

## Build

```bash
swift build            # binary at .build/debug/symoperate
swift run -q symoperate doctor
```

## CLI

```text
symoperate serve                          Run the MCP server over stdio
symoperate doctor                         Permission status + environment probes (JSON)
symoperate permissions status             Current macOS permissions
symoperate permissions grant accessibility
symoperate permissions grant screen
```

## MCP tools

`snapshot`, `query_ui`, `list_apps`, `list_windows`, `click`, `type_text`,
`press_keys`, `scroll`, `drag`, `launch_app`, `focus_window`, `menu_action`,
`wait_for`, `permissions_status`.

Register with an MCP host:

```json
{ "mcpServers": { "symoperate": { "command": "/abs/path/symoperate", "args": ["serve"] } } }
```

### Recommended agent loop

1. `query_ui` (or `snapshot`) → 2. decide → 3. prefer `element_id` over raw
coordinates → 4. one action → 5. re-snapshot before the next step.

## Safety

Supervised, local, stdio-only. Destructive controls (Delete/Trash/Uninstall/
Allow/Authorize/Unlock/Quit/…) and secure text fields are refused for
element-based actions. Don't automate passwords, payments, or permission dialogs
without explicit user confirmation. See [AGENTS.md](AGENTS.md) and `NOTICE`.

## Documentation

- [docs/architecture.md](docs/architecture.md) — components & tool contract
- [docs/roadmap.md](docs/roadmap.md) — built vs planned

## License

MIT © 2026 Daniel Justus.
