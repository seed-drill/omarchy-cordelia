# Cordelia for the Omarchy bar

[Cordelia](https://seeddrill.ai/cordelia) keeps your AI agent's memory in step
across your machines, end-to-end encrypted. This plugin puts it in the
[Omarchy](https://omarchy.org) bar: one icon that says whether memory is in
step, and a panel to manage it.

## What it shows

- **The icon:** Cordelia's mark while memory is in step, and dimmed while
  sync is off, the node is stopped or Cordelia is not set up. It gives way to
  a glyph while sending and while offline, and for the level the node gives.
  Red is for what to act on now (a conflict to merge, an error, a machine not
  added yet): a warning sign, which the bar highlights. Amber is for what to
  know of (a device added and not yet cleared, a relay without the latest
  change): the same sign in outline, in a milder colour. The mark is
  `assets/cordelia-mark.svg`, drawn in the bar's own colour.
- **The head of the panel:** the node's summary. Where anything holds, every
  thing that holds is listed in its place, red first, each as the node says
  it. If the running node is not the version of the command, the panel says
  so: restart the node. Until then changes are refused; turning sync off
  still works.
- **The switch:** memory sync on or off for this device.
- **Stopped syncing:** on a machine that had synced everything it found, the
  folders that stopped when only mapped folders came to sync. Each has a
  switch to map it again where the node says it can be mapped, and the node's
  reason where it cannot. A folder that needs a name from you has no switch:
  its row copies the command, for you to put the name in. No folder has a
  switch while sync is off. *I have seen this* puts the notice away.
- **Conflicts:** files two machines edited at once; click to open one.
- **Your devices:** each device by its label and the first words of its key's
  fingerprint, the devices added since the last change, and what this device
  has to tell you. A device that you removed is no longer listed:
  `cordelia devices` lists the removed keys. Cordelia adds and removes a
  device at a terminal, where it asks before it acts, so the panel copies
  each command and runs none of them:
  - click this device to copy its key;
  - click another device to copy `cordelia remove-device` with its key;
  - *Add a device* copies `cordelia add-device <key> --name <label>`, with the
    key filled in when the clipboard holds one (`cordelia id` prints it on the
    other machine);
  - *Clear these notices* copies `cordelia devices --clear`.

  On a machine with no recovery phrase yet, it shows the three ways on, each
  to copy:
  - `cordelia phrase`, if you have no phrase yet, on your most up to date
    machine;
  - `cordelia accept <key>`, after `cordelia add-device` on a machine that
    has the phrase;
  - `cordelia recover`, if you have lost every device. Do not make a new
    phrase first.
- **Syncing:** home memory first, with a switch of its own. Then each folder
  that syncs and the name it syncs under, with a switch to stop syncing it
  from this device. Only mapped folders sync.
- **Found on this machine:** folders Claude Code has memory for that do not
  sync. One has a switch only where the node says `cordelia sync map` would
  sync it; otherwise it shows the node's reason. A git project syncs under
  its remote, so the same project on another machine joins it; any other
  folder syncs under its own name.
- **On your other devices:** names your other devices sync that have no folder
  here. Click one to copy the command that syncs it to a folder.
- **Relays:** each relay this device is set up with, whether it is connected
  and for how long, and whether it holds the latest change of your devices.
- **At the foot:** one line. The version of Cordelia, the version of this
  panel, and how much memory this device stores. If the running node is not
  the command's version, both versions are shown. The amount is shown only
  beside a running node of the command's own version.

Keys in the panel: `s` toggles sync, `c` copies this device's key, `r`
refreshes, Tab moves to the next panel, Esc closes.

**On a Mac:** a native menu bar app, in [`macos/`](macos/README.md). It is
behind this panel, and is brought up to it next.

**In Waybar:** `cordelia status --waybar` prints text, so it keeps a Nerd Font
glyph for every state: a brain where this panel draws the mark.

## Install

Needs Cordelia `v0.2.0-alpha.9` or later.

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
`cordelia status --json`, and the sizes from `cordelia stats --json` when the
panel opens beside a running node of the command's own version. The level,
red or amber, is the node's: the panel draws it and works nothing out.
Everything it changes in Cordelia goes through the `cordelia` command line:
sync on and off, home memory, mapping and unmapping a folder, and putting the
notice away. A command that is refused says why in the panel. *Start the
node* is the one thing that does not go through it: it asks the service
manager (`systemctl --user start cordelia`). `Service.qml` does all of this;
`Panel.qml` is the bar button and the panel, built from Omarchy's own panel
components.

## License

MIT.
