# Cordelia for the macOS menu bar

The macOS twin of the Omarchy panel. A single [SwiftBar](https://swiftbar.app) plugin puts one icon in the menu bar. It shows whether memory is in step, and a menu manages it. The menu has the same sections, switches and commands as the panel.

## What it shows

- **The icon** shows synced, syncing, offline, off, or needs attention. It shows attention for a conflict, an error, or anything on your never-sync list that syncs anyway.
- **Sync, Home memory and Everything found** work as the switches in the panel do.
- **Conflicts to merge.** Click one to open it.
- **Relays,** with how long each has been connected.
- **Your devices.**
  - Click this device to copy its key.
  - Each other device has *Remove this device…*, which asks twice.
  - *Add a device from the clipboard* takes the other device's key, asks first, and puts the `cordelia accept` command for the other device on the clipboard.
- **Syncing.** Each folder that syncs, under its name. Click one to stop syncing it here.
- **Found on this machine.** Folders Claude Code has memory for that don't sync. Click one to start syncing it, after a confirmation.
- **On your other devices.** Names your other devices sync that have no folder here. Click one to copy the command that maps a folder to it.

## Install

Needs Cordelia `v0.2.0-alpha.3` or later. It uses the system `python3`, so nothing else needs installing.

```bash
brew install --cask swiftbar
git clone https://github.com/seed-drill/omarchy-cordelia.git ~/omarchy-cordelia
mkdir -p ~/.swiftbar
defaults write com.ameba.SwiftBar PluginDirectory ~/.swiftbar
ln -s ~/omarchy-cordelia/macos/cordelia.10s.py ~/.swiftbar/
open -a SwiftBar
```

The plugin is a symlink into the clone, so `git pull` updates it. The `10s` in the file name is how often SwiftBar refreshes it, and it also refreshes whenever the menu opens.

## Settings

Settings live in `~/.config/cordelia/menubar.json`. All keys are optional; see `menubar.example.json`.

| Key | Default | What |
|---|---|---|
| `command` | `~/.cordelia/bin/cordelia` | The cordelia binary to use |
| `never` | none | Names and folders this Mac must never sync from the menu |

### The never-sync list

This is not in the Omarchy panel. It is for a machine that holds memory which must not leave it.

Each entry is one of:
- `~` for home memory;
- a sync name, such as `github.com/your-company/*`, where a trailing `*` matches a prefix;
- a folder, written as `~/path` or `/path`.

While the list is set:
- Entries on it are greyed out, and clicking them does nothing.
- *Everything found* stays off.
- Anything on the list that syncs anyway turns the icon to attention, with a line saying what it is.

A file that can't be read counts as a list that matches everything, so a typo never widens what syncs.

The list guards the menu only. Nothing stops `cordelia sync map` typed in a terminal; that would need a never-sync list in the node.

## Keeping in step with the panel

`TRACKS` at the top of `cordelia.10s.py` is the panel commit this file matches. When `Service.qml` or `Panel.qml` changes:

```bash
git diff <TRACKS>..HEAD -- Service.qml Panel.qml
```

Port the change into `cordelia.10s.py` and move `TRACKS`. The two files map one to one:
- `model()` is the derived properties in `Service.qml`;
- `act()` is its command functions;
- `render()` is `Panel.qml`, section by section, in the same order and with the same words.

Neither widget holds any logic of its own about state. The icon state and summary come from the node (`status --json`: `state`, `summary`), so a change there reaches both without touching either.
