# Cordelia for the Omarchy bar

[Cordelia](https://seeddrill.ai/cordelia) keeps your AI agent's memory in step
across your machines, end-to-end encrypted. This plugin puts it in the
[Omarchy](https://omarchy.org) bar: one icon that says whether memory is in
step, and a panel to manage it.

## What it shows

- **The icon:** synced, sending, offline, or needs attention (a conflict to
  merge, or an error), which the bar highlights.
- **The switch:** memory sync on or off for this device. Below it, a switch
  for home memory and one for syncing everything Claude Code has memory for.
- **Relays:** which are connected, and for how long.
- **Your devices:** click this device to copy its key; add another device from
  a key on the clipboard; remove one (it asks twice, then changes the keys).
- **Syncing:** each folder that syncs and the name it syncs under, with a
  switch to stop syncing it from this device.
- **Found on this machine:** folders Claude Code has memory for that do not
  sync, each with a switch to start. A git project syncs under its remote, so
  the same project on another machine joins it; any other folder syncs under
  its own name.
- **On your other devices:** names your other devices sync that have no folder
  here. Click one to copy the command that syncs a folder with it.
- **Conflicts:** files two machines edited at once; click to open one.

Keys in the panel: `s` toggles sync, `c` copies this device's key, `r`
refreshes, Tab moves to the next panel, Esc closes.

**On a Mac:** the same panel as a menu bar icon, through SwiftBar. See
[`macos/`](macos/README.md).

## Install

Needs Cordelia `v0.2.0-alpha.3` or later (`cordelia status --json`).

```bash
omarchy plugin add https://github.com/seed-drill/omarchy-cordelia.git --enable
```

The icon appears on the right of the bar. Move it with `omarchy bar move
seeddrill.cordelia --before omarchy.agents`.

After updating the plugin, run `omarchy restart shell` if the panel still
shows the old layout.

## Settings

In the widget's entry in `~/.config/omarchy/shell.json`, or with
`omarchy bar set seeddrill.cordelia <key> <value>`:

| Key | Default | What |
|---|---|---|
| `refreshIntervalSec` | `10` | How often the icon refreshes (3 s while the panel is open) |
| `command` | `~/.cordelia/bin/cordelia` | The cordelia binary to use |

## How it works

The plugin holds no state. Everything it shows comes from
`cordelia status --json`, and everything it changes goes through the `cordelia`
command line. `Service.qml` does both; `Panel.qml` is the bar button and the
panel, built from Omarchy's own panel components.

## License

MIT.
