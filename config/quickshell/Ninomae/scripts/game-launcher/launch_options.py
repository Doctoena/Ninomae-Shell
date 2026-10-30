#!/usr/bin/env python3
"""Per-game Steam launch options, Proton version and auto-update mode, for the game launcher's "Launch options" panel.

  launch_options.py get <appid>               → JSON: current options, Proton choice, what's available
  launch_options.py set <appid> <json>        → writes {"launchOptions", "proton"} (Steam must be closed; see --restart)
  launch_options.py set <appid> <json> --restart
                                              → closes Steam, writes, starts Steam again
  launch_options.py uninstall <appid> [--restart] [--dry-run]
                                              → removes the game without Steam's confirmation dialog
  launch_options.py libraries                 → JSON: Steam's library folders, with free space
  launch_options.py install <appid> [--library <path>] [--restart] [--dry-run]
                                              → installs an owned game without Steam's install dialog
  launch_options.py leftovers                 → JSON: Proton prefixes and shader caches of uninstalled games
  launch_options.py remove-leftovers <appid>… → deletes those (only for games that aren't installed)
  launch_options.py roundtrip                 → self-test: parse + rewrite Steam's files unchanged

Launch options live in userdata/<account>/config/localconfig.vdf (…/apps/<appid>/LaunchOptions) and
Proton choices in config/config.vdf (CompatToolMapping/<appid>), and the auto-update mode in the game's
<library>/steamapps/appmanifest_<appid>.acf (AppState/AutoUpdateBehavior: 0 keep updated, 1 only on
launch, 2 high priority). Steam rewrites these files when it exits, so they're only edited while it's
closed. A copy of each file is kept before every write.

The options are stored exactly as typed, the same string Steam's own Launch Options box holds.
"""
import functools, json, os, re, shutil, subprocess, sys, time

STEAM = os.path.expanduser("~/.local/share/Steam")
BACKUP_DIR = os.path.expanduser("~/.cache/ninomae-launch-options")

# ── Valve KeyValues (VDF, text) ─────────────────────────────────────────────
# Parsed into lists of [key, value] pairs (value: str or a nested list), so key order and duplicates
# survive; written back in Steam's own layout (tabs), which round-trips its files unchanged.
_TOKEN = re.compile(r'\s*(?:(//[^\n]*)|("(?:[^"\\]|\\.)*")|([{}]))', re.S)

def _unquote(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s[1:-1])

def _quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def vdf_load(text):
    pos, stack, root, key = 0, [], [], None
    cur = root
    while True:
        m = _TOKEN.match(text, pos)
        if not m or m.end() == pos:
            if text[pos:].strip():
                raise ValueError(f"unexpected text at {pos}")
            break
        pos = m.end()
        comment, string, brace = m.groups()
        if comment:
            continue
        if string is not None:
            if key is None:
                key = _unquote(string)
            else:
                cur.append([key, _unquote(string)]); key = None
        elif brace == "{":
            child = []
            cur.append([key, child]); stack.append(cur); cur = child; key = None
        elif brace == "}":
            cur = stack.pop()
    return root

def vdf_dump(pairs, depth=0):
    out, tab = [], "\t" * depth
    for k, v in pairs:
        if isinstance(v, list):
            out.append(f"{tab}{_quote(k)}\n{tab}{{\n{vdf_dump(v, depth + 1)}{tab}}}\n")
        else:
            out.append(f"{tab}{_quote(k)}\t\t{_quote(v)}\n")
    return "".join(out)

def child(pairs, key, create=False):
    """The nested list under `key` (case-insensitive, as Steam treats keys)"""
    for k, v in pairs:
        if k.lower() == key.lower() and isinstance(v, list):
            return v
    if create:
        new = []; pairs.append([key, new]); return new
    return None

def path_in(pairs, keys, create=False):
    for k in keys:
        pairs = child(pairs, k, create)
        if pairs is None:
            return None
    return pairs

def get_value(pairs, key):
    for k, v in pairs:
        if k.lower() == key.lower() and isinstance(v, str):
            return v
    return None

def set_value(pairs, key, value):
    for item in pairs:
        if item[0].lower() == key.lower() and isinstance(item[1], str):
            if value is None: pairs.remove(item)
            else: item[1] = value
            return
    if value is not None:
        pairs.append([key, value])

# ── Steam files ─────────────────────────────────────────────────────────────
def account_dir():
    """userdata/<accountid> of the most recent login"""
    users = os.path.join(STEAM, "config", "loginusers.vdf")
    accounts = [d for d in os.listdir(os.path.join(STEAM, "userdata")) if d.isdigit() and d != "0"]
    try:
        for sid, data in vdf_load(open(users, encoding="utf-8").read())[0][1]:
            if isinstance(data, list) and get_value(data, "MostRecent") == "1":
                acc = str(int(sid) - 76561197960265728)
                if acc in accounts:
                    return os.path.join(STEAM, "userdata", acc)
    except Exception:
        pass
    return os.path.join(STEAM, "userdata", accounts[0]) if accounts else None

def localconfig_path():
    acc = account_dir()
    return os.path.join(acc, "config", "localconfig.vdf") if acc else None

CONFIG_VDF = os.path.join(STEAM, "config", "config.vdf")
APPS_KEYS = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"]
COMPAT_KEYS = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"]

def read_vdf(path):
    return vdf_load(open(path, encoding="utf-8").read())

def write_vdf(path, pairs):
    os.makedirs(BACKUP_DIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(path, os.path.join(BACKUP_DIR, f"{os.path.basename(path)}.{stamp}"))
    for old in sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith(os.path.basename(path) + "."))[:-10]:
        os.remove(os.path.join(BACKUP_DIR, old)) # Keep the last 10 of each
    tmp = path + ".ninomae.tmp"
    open(tmp, "w", encoding="utf-8").write(vdf_dump(pairs))
    os.replace(tmp, path)

def steam_running():
    return subprocess.run(["pgrep", "-x", "steam"], capture_output=True).returncode == 0

# ── Proton versions ─────────────────────────────────────────────────────────
@functools.cache # Asked for by both the Proton scan and the manifest lookup
def steam_libraries():
    libs = [STEAM]
    try:
        for _, lib in read_vdf(os.path.join(STEAM, "steamapps", "libraryfolders.vdf"))[0][1]:
            p = get_value(lib, "path") if isinstance(lib, list) else None
            if p and p not in libs: libs.append(p)
    except Exception:
        pass
    return libs

def proton_versions():
    found = []
    tools_dir = os.path.join(STEAM, "compatibilitytools.d")
    if os.path.isdir(tools_dir):
        for d in sorted(os.listdir(tools_dir)):
            vdf_file = os.path.join(tools_dir, d, "compatibilitytool.vdf")
            try:
                tools = path_in(read_vdf(vdf_file), ["compatibilitytools", "compat_tools"]) or []
                for name, info in tools:
                    found.append({"name": name, "label": get_value(info, "display_name") or name})
            except Exception:
                pass
    for lib in steam_libraries():
        common = os.path.join(lib, "steamapps", "common")
        if not os.path.isdir(common): continue
        for d in sorted(os.listdir(common)):
            m = re.match(r"^Proton (?:- )?(Experimental|Hotfix|(\d+)\.\d+)", d)
            if not m: continue
            name = "proton_" + (m.group(2) or m.group(1).lower())
            if not any(v["name"] == name for v in found):
                found.append({"name": name, "label": d})
    return found

def manifest_path(appid):
    """The installed game's appmanifest, in whichever library holds it (None when not installed)"""
    for lib in steam_libraries():
        p = os.path.join(lib, "steamapps", f"appmanifest_{appid}.acf")
        if os.path.exists(p):
            return p
    return None

def default_gamescope_args():
    try:
        mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True).stdout)
        m = next((x for x in mons if x.get("focused")), mons[0])
        return f"-f -W {m['width']} -H {m['height']} -r {round(m['refreshRate'])}"
    except Exception:
        return "-f"

# ── Commands ────────────────────────────────────────────────────────────────
def cmd_get(appid):
    lc = localconfig_path()
    options = ""
    if lc and os.path.exists(lc):
        app = path_in(read_vdf(lc), APPS_KEYS + [appid])
        options = (get_value(app, "LaunchOptions") if app else None) or ""
    proton = ""
    if os.path.exists(CONFIG_VDF):
        entry = path_in(read_vdf(CONFIG_VDF), COMPAT_KEYS + [appid])
        proton = (get_value(entry, "name") if entry else None) or ""
    auto_update = None
    manifest = manifest_path(appid)
    if manifest:
        state = child(read_vdf(manifest), "AppState")
        try: auto_update = int(get_value(state, "AutoUpdateBehavior") or 0) if state is not None else None
        except ValueError: auto_update = 0
    print(json.dumps({
        "appid": appid, "launchOptions": options, "proton": proton, "autoUpdate": auto_update,
        "protonVersions": proton_versions(),
        "tools": {t: shutil.which(b) is not None for t, b in
                  [("gamemode", "gamemoderun"), ("mangohud", "mangohud"), ("gamescope", "gamescope")]},
        "defaultGamescopeArgs": default_gamescope_args(),
        "steamRunning": steam_running(),
    }))

def close_steam():
    """Quits Steam and waits for it to write its files; False if it won't close"""
    subprocess.run(["steam", "-shutdown"], capture_output=True)
    for _ in range(60):
        if not steam_running(): break
        time.sleep(0.5)
    if steam_running():
        return False
    time.sleep(1) # Let it finish writing its files
    return True

def steam_closed_or_error(restart):
    """None once Steam is closed (closing it if restart allows), else the (error, exit code) to report"""
    if not steam_running(): return None
    if not restart: return ("steam-running", 2)
    return None if close_steam() else ("steam-wont-close", 1)

def start_steam():
    subprocess.Popen(["steam", "-silent"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)

def cmd_set(appid, data, restart):
    err = steam_closed_or_error(restart)
    if err:
        print(json.dumps({"ok": False, "error": err[0]})); return err[1]
    options = (data.get("launchOptions") or "").strip()
    lc = localconfig_path()
    if lc and os.path.exists(lc):
        tree = read_vdf(lc)
        set_value(path_in(tree, APPS_KEYS + [appid], create=True), "LaunchOptions", options)
        write_vdf(lc, tree)
    if os.path.exists(CONFIG_VDF):
        tree = read_vdf(CONFIG_VDF)
        mapping = path_in(tree, COMPAT_KEYS, create=True)
        mapping[:] = [item for item in mapping if item[0] != appid]
        if data.get("proton"):
            mapping.append([appid, [["name", data["proton"]], ["config", ""], ["priority", "250"]]])
        write_vdf(CONFIG_VDF, tree)
    manifest = manifest_path(appid)
    if manifest and data.get("autoUpdate") in (0, 1, 2):
        tree = read_vdf(manifest)
        state = child(tree, "AppState")
        if state is not None:
            set_value(state, "AutoUpdateBehavior", str(data["autoUpdate"]))
            write_vdf(manifest, tree)
    if restart:
        start_steam()
    print(json.dumps({"ok": True, "launchOptions": options}))
    return 0

def _uses_dir(path):
    """True when a running process has its executable or working folder inside path (the game is open)"""
    prefix = path + os.sep
    for pid in filter(str.isdigit, os.listdir("/proc")):
        for link in ("exe", "cwd"):
            try:
                target = os.readlink(f"/proc/{pid}/{link}")
            except OSError:
                continue
            if target == path or target.startswith(prefix):
                return True
    return False

def cmd_uninstall(appid, restart, dry_run=False):
    """What Steam's own uninstall removes, without its dialog: the manifest (Steam treats a game with none
    as not installed), the install folder, shader cache, Workshop mods and download leftovers. The Proton
    prefix (compatdata) stays: games without cloud saves keep their saves there. Steam rewrites manifests
    from memory when it quits, so this runs while it's closed (--restart closes and reopens it, in the tray)."""
    if not re.fullmatch(r"\d+", appid):
        print(json.dumps({"ok": False, "error": "bad-appid"})); return 1
    manifest = manifest_path(appid)
    if not manifest:
        print(json.dumps({"ok": False, "error": "not-installed"})); return 1
    steamapps = os.path.dirname(manifest)
    installdir = get_value(child(read_vdf(manifest), "AppState") or [], "installdir") or ""
    common = os.path.realpath(os.path.join(steamapps, "common"))
    game_dir = os.path.realpath(os.path.join(common, installdir)) if installdir else ""
    # Only ever a folder directly inside this library's common/ (never common/ itself, or a link elsewhere)
    if not installdir or os.path.dirname(game_dir) != common:
        print(json.dumps({"ok": False, "error": "unusual-location", "path": game_dir})); return 1
    if os.path.isdir(game_dir) and _uses_dir(game_dir):
        print(json.dumps({"ok": False, "error": "game-running"})); return 2
    remove = [p for p in (game_dir,
                          os.path.join(steamapps, "shadercache", appid),
                          os.path.join(steamapps, "downloading", appid),
                          os.path.join(steamapps, "temp", appid),
                          os.path.join(steamapps, "workshop", "content", appid),
                          os.path.join(steamapps, "workshop", f"appworkshop_{appid}.acf"))
              if os.path.lexists(p)]
    if dry_run:
        print(json.dumps({"ok": True, "dryRun": True, "manifest": manifest, "remove": remove})); return 0
    was_running = steam_running()
    err = steam_closed_or_error(restart)
    if err:
        print(json.dumps({"ok": False, "error": err[0]})); return err[1]
    # A copy of the manifest first (like every other write here), then the manifest: from then on Steam
    # sees the game as uninstalled, even if removing the files is interrupted
    os.makedirs(BACKUP_DIR, exist_ok=True)
    shutil.copy2(manifest, os.path.join(BACKUP_DIR, f"{os.path.basename(manifest)}.{time.strftime('%Y%m%d-%H%M%S')}"))
    os.remove(manifest)
    failed = []
    for p in remove:
        try:
            if os.path.isdir(p) and not os.path.islink(p): shutil.rmtree(p)
            else: os.remove(p)
        except OSError:
            failed.append(p)
    if was_running:
        start_steam()
    print(json.dumps({"ok": not failed, "removed": len(remove) - len(failed), "failed": failed}))
    return 0 if not failed else 1

def cmd_libraries():
    out = []
    for lib in steam_libraries():
        try:
            st = os.statvfs(lib)
            out.append({"path": lib, "free": st.f_bavail * st.f_frsize, "size": st.f_blocks * st.f_frsize})
        except OSError:
            pass
    print(json.dumps(out))

def cmd_install(appid, library, restart, dry_run=False):
    """Installs a game you own without Steam's install dialog: a manifest saying the game needs an update
    that has started (StateFlags 1026) goes into the chosen library, and Steam downloads it when it starts.
    Steam only reads new manifests on start, so it's started in the tray (closed first if it's running).
    The folder name comes from Steam's app info, the same one its own install would use."""
    if not re.fullmatch(r"\d+", appid):
        print(json.dumps({"ok": False, "error": "bad-appid"})); return 1
    if manifest_path(appid):
        print(json.dumps({"ok": False, "error": "already-installed"})); return 1
    libs = steam_libraries()
    library = library or libs[0]
    if library not in libs:
        print(json.dumps({"ok": False, "error": "unknown-library"})); return 1
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from steam_appinfo import apps, APPINFO
    try:
        info = apps({int(appid)}, APPINFO).get(int(appid)) or {}
    except OSError:
        info = {}
    installdir = (info.get("config") or {}).get("installdir") or ""
    name = (info.get("common") or {}).get("name") or ""
    if not installdir or "/" in installdir or installdir in (".", ".."):
        print(json.dumps({"ok": False, "error": "no-app-info"})); return 1
    manifest = os.path.join(library, "steamapps", f"appmanifest_{appid}.acf")
    tree = [["AppState", [["appid", appid], ["Universe", "1"], ["name", name], ["StateFlags", "1026"],
                          ["installdir", installdir], ["LastUpdated", "0"], ["SizeOnDisk", "0"], ["buildid", "0"],
                          ["BytesToDownload", "0"], ["BytesDownloaded", "0"], ["AutoUpdateBehavior", "0"],
                          ["AllowOtherDownloadsWhileRunning", "0"], ["ScheduledAutoUpdate", "0"],
                          ["UserConfig", []], ["MountedConfig", []]]]]
    if dry_run:
        print(json.dumps({"ok": True, "dryRun": True, "manifest": manifest, "text": vdf_dump(tree)})); return 0
    err = steam_closed_or_error(restart)
    if err:
        print(json.dumps({"ok": False, "error": err[0]})); return err[1]
    os.makedirs(os.path.dirname(manifest), exist_ok=True)
    tmp = manifest + ".ninomae.tmp"
    open(tmp, "w", encoding="utf-8").write(vdf_dump(tree))
    os.replace(tmp, manifest)
    start_steam() # Steam has to be running to download, whether or not it was open before
    print(json.dumps({"ok": True, "manifest": manifest}))
    return 0

# ── Leftovers of uninstalled games ──────────────────────────────────────────
# Uninstalling keeps a game's Proton prefix (compatdata/<appid>: saves of games without Steam Cloud live
# there) and Steam leaves its shader cache. These are listed and deleted on request. Only real Steam apps
# count (in Steam's app info): non-Steam games added to Steam have prefixes and no manifest, yet are
# installed; prefix 0 is Steam's own for things that aren't Steam games.
LEFTOVER_KINDS = ("compatdata", "shadercache")

def _disk_usage(path):
    total = 0
    for dirpath, _, files in os.walk(path): # Links aren't followed (prefixes link into the system)
        for f in files:
            try: total += os.lstat(os.path.join(dirpath, f)).st_blocks * 512
            except OSError: pass
    return total

def _leftover_dirs():
    """{appid: [paths]} of uninstalled games' prefixes/caches, in every library"""
    found = {}
    for lib in steam_libraries():
        steamapps = os.path.join(lib, "steamapps")
        installed = {f[12:-4] for f in os.listdir(steamapps) if f.startswith("appmanifest_") and f.endswith(".acf")} \
            if os.path.isdir(steamapps) else set()
        for kind in LEFTOVER_KINDS:
            base = os.path.join(steamapps, kind)
            if not os.path.isdir(base): continue
            for d in os.listdir(base):
                if d.isdigit() and d != "0" and d not in installed and not manifest_path(d):
                    found.setdefault(d, []).append(os.path.join(base, d))
    return found

def cmd_leftovers():
    found = _leftover_dirs()
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from steam_appinfo import apps, APPINFO
    try:
        info = apps({int(a) for a in found}, APPINFO)
    except OSError:
        info = {}
    out = []
    for appid, paths in found.items():
        name = ((info.get(int(appid)) or {}).get("common") or {}).get("name")
        if not name: continue # Not a Steam app (see above)
        out.append({"appid": appid, "name": name, "size": sum(_disk_usage(p) for p in paths),
                    "modified": int(max(os.path.getmtime(p) for p in paths))})
    out.sort(key=lambda e: -e["size"])
    print(json.dumps(out))

def cmd_remove_leftovers(appids):
    found = _leftover_dirs()
    freed, failed = 0, []
    for appid in appids:
        if not appid.isdigit() or appid == "0" or appid not in found: # Installed, unknown, or already gone
            failed.append(appid); continue
        for p in found[appid]:
            size = _disk_usage(p)
            try:
                shutil.rmtree(p); freed += size
            except OSError:
                failed.append(appid)
    print(json.dumps({"ok": not failed, "freed": freed, "failed": failed}))
    return 0 if not failed else 1

def cmd_roundtrip():
    ok = True
    manifests = [os.path.join(lib, "steamapps", f) for lib in steam_libraries()
                 for f in sorted(os.listdir(os.path.join(lib, "steamapps")))
                 if f.startswith("appmanifest_") and f.endswith(".acf")]
    for p in [localconfig_path(), CONFIG_VDF] + manifests:
        if not p or not os.path.exists(p): continue
        text = open(p, encoding="utf-8").read()
        same = vdf_dump(vdf_load(text)) == text
        ok &= same
        print(("same   " if same else "DIFFERS"), p)
    return 0 if ok else 1

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["get"] and len(a) == 2: cmd_get(a[1])
    elif a[:1] == ["set"] and len(a) >= 3: sys.exit(cmd_set(a[1], json.loads(a[2]), "--restart" in a[3:]))
    elif a[:1] == ["uninstall"] and len(a) >= 2: sys.exit(cmd_uninstall(a[1], "--restart" in a[2:], "--dry-run" in a[2:]))
    elif a[:1] == ["libraries"]: cmd_libraries()
    elif a[:1] == ["leftovers"]: cmd_leftovers()
    elif a[:1] == ["remove-leftovers"] and len(a) >= 2: sys.exit(cmd_remove_leftovers(a[1:]))
    elif a[:1] == ["install"] and len(a) >= 2:
        lib = a[a.index("--library") + 1] if "--library" in a[2:] and a.index("--library") + 1 < len(a) else None
        sys.exit(cmd_install(a[1], lib, "--restart" in a[2:], "--dry-run" in a[2:]))
    elif a[:1] == ["roundtrip"]: sys.exit(cmd_roundtrip())
    else: print(__doc__); sys.exit(1)
