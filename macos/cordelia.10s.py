#!/usr/bin/python3
# <xbar.title>Cordelia</xbar.title>
# <xbar.version>v0.1.0</xbar.version>
# <xbar.author>Seed Drill</xbar.author>
# <xbar.author.github>seed-drill</xbar.author.github>
# <xbar.desc>Cordelia memory sync in the macOS menu bar: the SwiftBar twin of the Omarchy panel.</xbar.desc>
# <xbar.dependencies>python3,cordelia v0.2.0-alpha.3 or later</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>
"""Cordelia for the macOS menu bar (SwiftBar).

This is the macOS twin of the Omarchy panel (../Service.qml and ../Panel.qml).
Like the panel, it holds no state:
- everything it shows comes from `cordelia status --json`;
- everything it changes goes through the cordelia command line.

SwiftBar runs this file every 10 seconds to draw the menu. When an item is
clicked, it runs the file again with arguments.

Fast follow: TRACKS is the panel commit this file matches. When the panel
changes, read `git diff TRACKS..HEAD -- Service.qml Panel.qml`, port the change
here, and move TRACKS.

Two additions the panel doesn't have:
- A never-sync list in ~/.config/cordelia/menubar.json. Names and folders on it
  can't be switched on from the menu, and "Everything found" stays off while
  the list is set. If something on the list syncs anyway, the icon shows
  attention.
- Anything that widens what syncs, or adds or removes a device, asks first.
"""

import json
import os
import re
import subprocess
import sys

TRACKS = "1ee44bb"

HOME = os.path.expanduser("~")
CONFIG = os.path.join(HOME, ".config", "cordelia", "menubar.json")
PLIST = os.path.join(HOME, "Library", "LaunchAgents", "ai.seeddrill.cordelia.plist")
SELF = os.path.realpath(sys.argv[0])
URGENT = "#e5484d"
DIM = "#8e8e93"

# The icon for each state the node reports (status.state). The panel uses Nerd
# Font glyphs; these are the SF Symbols equivalents.
SYMBOLS = {
    "synced": "brain",
    "syncing": "arrow.triangle.2.circlepath",
    "offline": "icloud.slash",
    "attention": "exclamationmark.triangle.fill",
    "off": "moon.zzz",
    "stopped": "moon.zzz",
    "uninitialised": "brain",
}


def load_config():
    """The settings file, or {} if there is none. A file that can't be read
    counts as a never-sync list that matches everything, so a broken file
    never lets anything widen."""
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        return {"never": ["*"], "broken": True}
    return cfg if isinstance(cfg, dict) else {"never": ["*"], "broken": True}


CFG = load_config()
CLI = os.path.expanduser(str(CFG.get("command") or "~/.cordelia/bin/cordelia"))
NEVER = [str(p).strip() for p in (CFG.get("never") or []) if str(p).strip()]


# ── The node ─────────────────────────────────────────────────────────────


def run(args, timeout=60):
    try:
        r = subprocess.run([CLI] + list(args), capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def status():
    """The node's answer to `status --json`, or {} if there is no node."""
    code, out, _ = run(["status", "--json"], timeout=8)
    if code != 0 or not out.strip():
        return {}
    try:
        return json.loads(out)
    except ValueError:
        return {}


def model(st):
    """What the menu shows, derived as Service.qml derives it."""
    s = st.get("sync") or {}
    syncing = s.get("projects") if isinstance(s.get("projects"), list) else []
    available = s.get("available") if isinstance(s.get("available"), list) else []
    home_entry = next((p for p in syncing if p.get("project") == "~"), None)
    # Memory found here that does not sync, each with the name it would get.
    found = []
    for e in s.get("unmapped") or []:
        if not e.get("cwd") or e.get("name") == "~":
            continue
        # The node refuses to map a folder outside the home directory, so don't offer one.
        if not (str(e["cwd"]) == HOME or str(e["cwd"]).startswith(HOME + "/")):
            continue
        name = str(e["name"]) if e.get("name") else suggested_name(e["cwd"])
        if name:
            found.append({"cwd": str(e["cwd"]), "name": name, "named": bool(e.get("name"))})
    found_names = {f["name"] for f in found}
    return {
        "state": str(st.get("state") or "uninitialised"),
        "summary": str(st.get("summary") or ""),
        "installed": bool(st) and st.get("state") != "uninitialised",
        "running": st.get("running") is True,
        "sync_on": s.get("enabled") is True,
        "syncing": syncing,
        "home_entry": home_entry,
        "home": home_entry is not None,
        "projects": [p for p in syncing if p.get("project") != "~"],
        "knows_mappings": "all" in s,
        "all": s.get("all") is True,
        # Folders in the exclude list were unmapped; they show under "found".
        "excluded": [x for x in (s.get("exclude") or []) if not str(x).startswith("/")],
        "conflicts": s.get("conflicts") if isinstance(s.get("conflicts"), list) else [],
        "home_available": "~" in available,
        "found": found,
        # Names synced elsewhere with no folder found for them here.
        "elsewhere": [n for n in available if n != "~" and n not in found_names],
        "devices": st.get("devices") if isinstance(st.get("devices"), list) else [],
        "relays": [p for p in ((st.get("peers") or {}).get("list") or []) if p.get("role") == "relay"],
        "device_key": str(st.get("device") or ""),
        "waiting": int(st.get("outbox_waiting") or 0),
        "version": str(st.get("version") or ""),
    }


# ── The never-sync list ──────────────────────────────────────────────────


def _match(pattern, value):
    return value.startswith(pattern[:-1]) if pattern.endswith("*") else value == pattern


def on_never(name=None, cwd=None):
    """Whether a sync name or folder is on the never-sync list. `~` is home
    memory; an entry starting with / or ~/ is a folder; anything else is a
    name, with a trailing * matching a prefix."""
    for pat in NEVER:
        if pat == "~":
            if name == "~":
                return True
        elif pat.startswith(("/", "~/")):
            if cwd and _match(os.path.expanduser(pat), str(cwd)):
                return True
        elif name and _match(pat.lower(), str(name).lower()):
            return True
    return False


def violations(m):
    """Anything that syncs although the never-sync list rules it out."""
    out = []
    if NEVER and m["all"]:
        out.append("Everything found")
    for p in m["syncing"]:
        if on_never(p.get("project"), p.get("cwd")):
            out.append(project_label(p.get("project")))
    return out


# ── Text, as the panel writes it ─────────────────────────────────────────


def suggested_name(cwd):
    """The name a folder that is not a git project is offered under: its own
    name, in the characters a sync name allows. "" if nothing usable is left."""
    base = next((p for p in reversed(str(cwd or "").split("/")) if p), "")
    name = re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9._-]+", "-", base.lower()))
    return name if re.search(r"[a-z0-9]", name) else ""


def short_path(path):
    p = str(path or "")
    return "~" + p[len(HOME):] if p == HOME or p.startswith(HOME + "/") else p


def short_key(key):
    k = str(key or "")
    return k[:18] + "…" + k[-6:] if len(k) > 26 else k


def duration(secs):
    s = int(secs or 0)
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m"
    if s < 86400:
        return f"{s // 3600}h {(s % 3600) // 60}m"
    return f"{s // 86400}d"


def file_name(path):
    return str(path or "").split("/")[-1]


def project_label(project):
    return "Home memory" if project == "~" else str(project or "")


def elide(text):
    value = " ".join(str(text or "").split())
    return value[:157] + "…" if len(value) > 160 else value


# ── The menu ─────────────────────────────────────────────────────────────


def line(title, **params):
    parts = []
    for k, v in params.items():
        if v is None or v is False:
            continue
        v = "true" if v is True else str(v).replace('"', "'")
        parts.append(f'{k}="{v}"' if (" " in v or "=" in v or v == "") else f"{k}={v}")
    title = str(title).replace("|", "¦")
    print(title + (" | " + " ".join(parts) if parts else ""))


def action(title, *args, **params):
    """A menu item that runs this file again with `args`."""
    ps = {f"param{i + 1}": str(a) for i, a in enumerate(args)}
    line(title, bash=SELF, terminal="false", refresh=True, **ps, **params)


def header(text):
    print("---")
    line(text, size=11, color=DIM)


def item(title, detail=None, *args, **params):
    """A row as the panel draws it: a title, and a small grey line under it.
    With `args`, clicking the title runs this file with them."""
    if args:
        action(title, *args, **params)
    else:
        line(title, **params)
    if detail:
        line(detail, size=11, color=DIM)


def render():
    st = status()
    m = model(st)
    bad = violations(m)
    state = "attention" if bad else m["state"]
    bar = {"sfimage": SYMBOLS.get(state, "brain"), "tooltip": m["summary"] or "Cordelia"}
    if state == "attention":
        bar["sfcolor"] = URGENT
    line("", **bar)
    print("---")

    if not m["installed"]:
        item("Cordelia", "Install it to keep your agent's memory in step across your machines",
             href="https://seeddrill.ai/install")
        return

    # ── The header: the switch is memory sync itself ──
    about = f"cordelia {m['version'] or '?'} · panel {TRACKS}"
    summary = (m["summary"] or m["state"]).upper()
    if m["running"]:
        item("Cordelia", summary, "toggle-sync", checked=m["sync_on"], size=14,
             tooltip=("Stop syncing memory on this device" if m["sync_on"] else "Sync Claude Code's memory") + f" ({about})")
    else:
        item("Cordelia", summary, size=14, tooltip=about)
        item("Start the node", "It runs in the background and keeps memory in step", "start-node")
    for v in bad:
        line(f"On your never-sync list, and syncing: {v}", color=URGENT)
    if CFG.get("broken"):
        line("menubar.json can't be read, so everything counts as never-sync", color=URGENT)
    if not m["running"]:
        return

    if m["sync_on"]:
        print("---")
        if on_never("~") and not m["home"]:
            item("Home memory", "Kept off this device (never-sync list)")
        else:
            if m["home"]:
                detail = ("Waiting for one of your other devices to let this one in"
                          if (m["home_entry"] or {}).get("waiting") is True
                          else "What Claude remembers outside any project")
            else:
                detail = ("Your other devices sync it" if m["home_available"]
                          else "What Claude remembers outside any project")
            item("Home memory", detail, "home", "off" if m["home"] else "on", checked=m["home"])
        if m["knows_mappings"]:
            if NEVER and not m["all"]:
                item("Everything found", "Off: only the folders you turn on below (never-sync list set)")
            else:
                item("Everything found",
                     "Home memory and every git project, now and later" if m["all"]
                     else "Off: only the folders you turn on below",
                     "all", "off" if m["all"] else "on", checked=m["all"])
        if m["waiting"] > 0:
            item(f"Waiting to send: {m['waiting']}")

    # ── Conflicts ──
    if m["conflicts"]:
        header("CONFLICTS TO MERGE")
        for c in m["conflicts"]:
            item(file_name(c), "Two machines edited this at once. Merge it, then delete this file.", "open", c)

    # ── Relays ──
    header("RELAYS")
    if not m["relays"]:
        item("No relay connected. Changes wait here until one is.")
    for r in m["relays"]:
        item(f"{short_key(r.get('key'))}      connected {duration(r.get('connected_secs'))}",
             tooltip=str(r.get("key") or ""))

    # ── Devices ──
    header("YOUR DEVICES")
    for d in m["devices"]:
        mine = d.get("this_device") is True
        title = (str(d.get("name")) if d.get("name") else short_key(d.get("key"))) + ("  (this device)" if mine else "")
        if mine:
            item(title, "Click to copy this device's key", "copy-key")
        else:
            line(title)
            action("--Remove this device…", "remove-device", d.get("key"),
                   tooltip="Asks twice, then changes the keys on every channel")
            if d.get("in_personal_channel") is not True:
                detail = "Trusted, waiting for it to join"
            else:
                detail = short_key(d.get("key")) if d.get("name") else "Another of your devices"
            line(detail, size=11, color=DIM)
    item("Add a device from the clipboard", "Copy the other device's key (cordelia id), then click", "add-device")

    if not m["sync_on"]:
        return

    # ── Syncing ──
    header("SYNCING")
    if not m["projects"] and not m["excluded"]:
        item("Nothing syncs yet", "Turn on a folder below")
    for p in m["projects"]:
        title = short_path(p["cwd"]) if p.get("cwd") else project_label(p.get("project"))
        if p.get("error"):
            detail = f"Error: {p['error']}"
        elif p.get("waiting") is True:
            detail = "Waiting for one of your other devices to let this one in"
        else:
            detail = str(p.get("project")) if p.get("cwd") else "Syncing"
        item(title, detail, "stop", p.get("project"), "mapped" if p.get("mapped") is True else "found",
             checked=True, color=URGENT if p.get("error") else None, tooltip="Click to stop syncing it here")
    for x in m["excluded"]:
        if on_never(x):
            item(str(x), "Kept off this device (never-sync list)")
        else:
            item(str(x), "Kept off this device", "include", x, checked=False, tooltip="Click to sync it again")

    # ── Found here ──
    if m["found"]:
        header("FOUND ON THIS MACHINE")
        for f in m["found"]:
            detail = f["name"] if f["named"] else f"Syncs as {f['name']}"
            if on_never(f["name"], f["cwd"]):
                item(short_path(f["cwd"]), f"{detail} · never-sync list")
            else:
                item(short_path(f["cwd"]), detail, "map", f["cwd"], f["name"],
                     "named" if f["named"] else "unnamed", checked=False,
                     tooltip="Click to start syncing it. Asks first.")

    # ── Elsewhere ──
    if m["elsewhere"]:
        header("ON YOUR OTHER DEVICES")
        for n in m["elsewhere"]:
            item(str(n), "Click to copy the command that syncs a folder with it",
                 "copy", f"cordelia sync map <folder> {n}")


# ── Actions ──────────────────────────────────────────────────────────────


def _osa_text(text):
    return str(text).replace("\\", "\\\\").replace('"', '\\"')


def notify(text):
    subprocess.run(["/usr/bin/osascript", "-e",
                    f'display notification "{_osa_text(elide(text))}" with title "Cordelia"'],
                   capture_output=True)


def confirm(text, ok):
    script = (f'display dialog "{_osa_text(text)}" with title "Cordelia" '
              f'buttons {{"Cancel", "{_osa_text(ok)}"}} default button "Cancel" '
              f'cancel button "Cancel" with icon caution')
    return subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True).returncode == 0


def pbcopy(text):
    subprocess.run(["/usr/bin/pbcopy"], input=str(text), text=True)


def pbpaste():
    return subprocess.run(["/usr/bin/pbpaste"], capture_output=True, text=True).stdout


def finish(result, show="last"):
    """Report a finished command the way the panel does: the error, or the
    first or last line of its output."""
    code, out, err = result
    if code != 0:
        notify(err or out or "The command failed")
        return
    lines = out.strip().splitlines()
    if lines and show == "first":
        notify(lines[0])
    elif lines and show == "last":
        notify(lines[-1])


def act(a, rest):
    arg = lambda i: rest[i] if len(rest) > i else ""
    if a == "toggle-sync":
        # Turning sync on again keeps the mappings and the scope set before.
        if model(status())["sync_on"]:
            finish(run(["sync", "off"]))
        else:
            finish(run(["sync", "claude"]), show="none")
    elif a == "home":
        on = arg(0) == "on"
        if on and on_never("~"):
            return notify("Home memory is on your never-sync list")
        if on and not confirm("Sync home memory on this device? It goes to every device that syncs home memory.",
                              "Sync home memory"):
            return
        finish(run(["sync", "home", "on" if on else "off"]))
    elif a == "all":
        on = arg(0) == "on"
        if on and NEVER:
            return notify("Everything found stays off while a never-sync list is set")
        if on and not confirm("Sync everything found? Home memory and every git project on this Mac, now and later.",
                              "Sync everything"):
            return
        finish(run(["sync", "claude", "--all" if on else "--mapped-only"]), show="none")
    elif a == "map":
        cwd, name, named = arg(0), arg(1), arg(2) == "named"
        if not cwd or not name:
            return
        if on_never(name, cwd):
            return notify(f"{short_path(cwd)} is on your never-sync list")
        if not confirm(f"Start syncing {short_path(cwd)} as {name}? Claude's memory for it will go to all your devices.",
                       "Start syncing"):
            return
        # A git project is named by its remote; any other folder is given its name.
        finish(run(["sync", "map", cwd] + ([] if named else [name])), show="first")
    elif a == "stop":
        # A mapped folder is unmapped; one found because everything syncs is excluded here.
        if arg(1) == "mapped":
            finish(run(["sync", "unmap", arg(0)]), show="first")
        else:
            finish(run(["sync", "exclude", arg(0)]))
    elif a == "include":
        if on_never(arg(0)):
            return notify(f"{arg(0)} is on your never-sync list")
        finish(run(["sync", "include", arg(0)]))
    elif a == "copy-key":
        key = str(status().get("device") or "")
        if key:
            pbcopy(key)
            notify("This device's key is on the clipboard")
    elif a == "copy":
        pbcopy(arg(0))
        notify(f"Copied: {arg(0)}")
    elif a == "add-device":
        # Pairing takes one key copied in each direction. The other device's key
        # comes from the clipboard; the command it must run goes back onto it.
        key = re.sub(r"\s+", "", pbpaste())
        if not key.startswith("cordelia_pk1"):
            return notify("The clipboard does not hold a device key (cordelia_pk1…)")
        if not confirm(f"Add {short_key(key)} as one of your devices? It will receive the memory this device syncs.",
                       "Add device"):
            return
        code, out, err = run(["add-device", key])
        if code != 0:
            return notify(err or out or "Adding the device failed")
        accept = next((l.strip() for l in out.splitlines() if l.strip().startswith("cordelia accept ")), "")
        if accept:
            pbcopy(accept)
        notify("Added. The command for the other device is on the clipboard.")
    elif a == "remove-device":
        key = arg(0)
        if not key:
            return
        if not confirm(f"Remove {short_key(key)}? It stops receiving memory.", "Continue"):
            return
        if not confirm(f"Remove {short_key(key)} for good? This changes the keys on every channel.", "Remove"):
            return
        notify("Removing the device and changing keys…")
        finish(run(["remove-device", key], timeout=180))
    elif a == "open":
        if arg(0):
            subprocess.run(["/usr/bin/open", "-t", arg(0)])
    elif a == "start-node":
        target = f"gui/{os.getuid()}/ai.seeddrill.cordelia"
        if subprocess.run(["/bin/launchctl", "kickstart", "-k", target], capture_output=True).returncode != 0:
            subprocess.run(["/bin/launchctl", "load", PLIST], capture_output=True)
        notify("Starting the node…")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        act(sys.argv[1], sys.argv[2:])
    else:
        render()
