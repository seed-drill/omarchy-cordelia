# Cordelia for the macOS menu bar

The macOS twin of the Omarchy panel: a small native app that puts one icon in the menu bar, showing whether memory is in step, with a short menu to manage it. The menu covers the panel's sections in a handful of rows, and the detail sits in submenus.

## What it shows

- **The icon** is Cordelia's mark, a brain seen from above, while memory is in step. It changes to turning arrows while syncing and a crossed cloud when no relay can be reached. A red warning triangle is for what to act on now: what the node calls red (a conflict, an error, a device with no recovery phrase yet), something on your never-sync list that syncs anyway, or a node that macOS will not start at the next login. The same triangle in outline, not coloured, is the node's amber: something to know of, such as a device that was added. The icon is dimmed where nothing is being passed on: sync off, the node stopped, or no relay connected. The mark is our own drawing (`assets/cordelia-mark.svg`), and the app icon is drawn from it: Apple's terms keep SF Symbols out of app icons and logos. The passing states use SF Symbols, as any menu may.
- **Status** is the node's own summary. Where anything holds, each thing is listed in its place as the node says it, red first, then amber.
- **A node of another version than the command** is said in red, with what to do: restart the node.
- **Allow Cordelia to Start at Login…** appears, in red, when macOS has the node's background item switched off in Login Items. The node can be running now, because an installer started it by hand, and still not be started at the next login; memory then stops syncing without a word. Click the row to open Login Items, and switch `cordelia` on. This is the one thing the menu shows that the node cannot report itself.
- **Sync Memory on This Mac** is the switch, like the panel's header.
- **Folders Stopped Syncing** appears while the node carries its notice of the folders that stopped when only mapped folders came to sync. Turn on the ones to keep, then *I Have Seen This* puts the notice away.
- **The folders that sync** are ticked. Click one to stop syncing it here; it asks first. Only mapped folders sync. Hover over one to see the name it syncs under, or why it did not sync.
- **Sync Another Folder** lists:
  - folders Claude Code has memory for that the node says it can map. Starting one asks first;
  - a folder that needs a name from you: a click copies the command, for a terminal;
  - home memory, when it can be turned on;
  - names your other devices sync. Click one to copy the command that maps a folder to it;
  - *Found Here, Cannot Be Mapped*: the rest, each with the node's reason.
- **Your Devices** are the devices under your recovery phrase, as the node lists them: those of the last change, those added since, and removed keys. Nothing here runs `cordelia phrase`, `add-device`, `accept`, `remove-device` or `devices --clear`: each asks at a terminal, so the menu copies the command and runs nothing.
  - Click this device to copy its key.
  - Each other device has *Copy the Command That Removes It*.
  - *Add a Device* copies `cordelia add-device <key> --name <label>`, with the other device's key in it where the clipboard holds a key and nothing else.
  - A device with no recovery phrase yet shows the two ways on: `cordelia phrase`, or `cordelia accept <key>` after `add-device` on a machine that has the phrase.
  - What the node has to tell you is listed, with *Clear These Notices*, which copies `cordelia devices --clear`.
- **Relays** lists each relay by name with whether it is connected, for how long, and whether it holds the latest change of your devices. A relay that is not connected shows in red.
- **Conflicts to Merge** appears when there are any. Click one to open it.
- **The last line** gives the command's version, the running node's, and this menu's.
- **Quit Cordelia Menu** closes the menu bar app only. The node keeps running and memory keeps syncing.

Hover over any row to see what it does. Each action shows a notification. Every click and its outcome are logged to `~/.cordelia/logs/menubar.log`, so a click that did nothing can be seen.

## Install

Needs Cordelia `v0.2.0-alpha.9` or later, macOS 13 or later, and the Xcode command line tools (`xcode-select --install`). There is nothing else to install.

```bash
git clone https://github.com/seed-drill/omarchy-cordelia.git ~/omarchy-cordelia
~/omarchy-cordelia/macos/app/install.sh
```

The script:
- builds `Cordelia.app` and puts it in `~/Applications`;
- opens it now and at every login, as a login item of its own. It is listed by name under *System Settings › General › Login Items › Open at Login*, apart from the node's background item, and can be removed there;
- removes the link to the earlier SwiftBar plugin if there is one, so there are not two icons.

macOS asks once whether Cordelia may send notifications. If you decline, they are still sent, but appear as Script Editor's.

The app is built on your Mac and signed for that Mac only. There is no developer identity behind it, which is why it is built here and not downloaded.

To update, `git pull` and run `install.sh` again. To remove it, run `macos/app/uninstall.sh`.

## Settings

Settings live in `~/.config/cordelia/menubar.json`. All keys are optional; see `menubar.example.json`. The file is read again every time the menu opens.

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
- Entries on it aren't offered. The menu only counts them.
- Anything on the list that syncs anyway turns the icon to attention, with a line saying what it is.

A file that can't be read counts as a list that matches everything, so a typo never widens what syncs.

The list guards the menu only. Nothing stops `cordelia sync map` typed in a terminal; that would need a never-sync list in the node.

## Keeping in step with the panel

`TRACKS` at the top of `app/Sources/Model.swift` is the panel commit this app matches. When `Service.qml` or `Panel.qml` changes:

```bash
git diff <TRACKS>..HEAD -- Service.qml Panel.qml
```

Port the change and move `TRACKS`. The files map one to one:

| Here | The panel |
|---|---|
| `Model.swift` | the derived properties in `Service.qml` |
| `Actions.swift` | its command functions |
| `MenuTree.swift` | the sections of `Panel.qml`, with its words, as menu rows |
| `App.swift` | draws the rows as a native menu; no logic of its own |

Neither widget holds any logic of its own about state. The icon, the summary and what holds come from the node (`status --json`: `state`, `summary`, `level`, `holds`), so a change there reaches both without touching either.

The panel shows the sizes of what this device holds, from `cordelia stats --json`. This app does not: `stats` opens the database itself and brings it to the command's own version, so it must never run beside a node of another version.

## Tests

The menu is built as data before it is drawn, so it can be checked without a screen:

```bash
macos/app/build.sh
macos/app/tests/run.sh
```

Each `.status.json` in `tests/fixtures/` is a saved `status --json`, some with a settings file or extra arguments beside them, and `tests/expected/` holds the menu the app draws for it, as text, with the `cordelia` command each row runs. After a deliberate change, `run.sh --update` rewrites the expected files; read the diff before committing it.

The fixtures are written by hand in the shape `status --json` has at `v0.2.0-alpha.9`, with made-up people, keys and hosts. They hold what the app reads, and their wording is not the node's.

`Cordelia.app/Contents/MacOS/Cordelia --dump-menu` prints the menu for the node on this Mac. `--dump-about` prints what the About window says: the node's version at the top, the menu's own beneath. `--dump-add-device` prints what *Add a Device* would copy for a given clipboard.
