# herdr-safe-close

Close the current tab or pane in [herdr](https://herdr.dev), but ask first
when closing it would kill something.

Herdr's built-in `close_tab` / `close_pane` close immediately. Safe Close
checks every pane in the target first:

- **All idle shells**: closes right away, no prompt.
- **Anything in the foreground** (an agent, a dev server, an editor, ssh...):
  opens a small popup listing what is running.
- **Last tab in its space**: always asks, since closing it closes the space.

```
┌ close ─────────────────────────────────────┐
│                                            │
│  ● last tab — closing it closes the space  │
│  ● claude (idle)                           │
│                                            │
│  Close this tab?                           │
│                                            │
│  [y] close   [n] cancel                    │
└────────────────────────────────────────────┘
```

`y` or Enter closes; any other key cancels.

A pane counts as busy when its foreground process group is not the shell
itself (`herdr pane process-info`), or when herdr has detected an agent in it.

## Install

```bash
herdr plugin install RodrigoEspinosa/herdr-safe-close
```

Requires `bash` and [`jq`](https://jqlang.org).

## Keybindings

The plugin only provides actions; bind them in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "cmd+w"
type = "plugin_action"
command = "herdr-safe-close.close-tab"
description = "close tab (confirm if busy)"

[[keys.command]]
key = "cmd+shift+w"
type = "plugin_action"
command = "herdr-safe-close.close-pane"
description = "close pane (confirm if busy)"
```

If those keys are already assigned (for example to `close_pane`), remove the
old bindings. Then run `herdr server reload-config`.

`cmd` bindings need a terminal that passes Cmd through to herdr (for
example, Ghostty with `keybind = clear`).

## License

MIT
