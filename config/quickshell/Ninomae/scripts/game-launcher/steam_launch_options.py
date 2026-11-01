#!/usr/bin/env python3
"""A Steam game's launch options, for the launcher to ask which one instead of Steam's dialog
(Project Zomboid: "Play" or "Compatibility Mode"). Prints a JSON list, [] with one option or none:

  [{"index": <n>, "label": <its name>, "detail": <its arguments or program>}, …]

Launched as steam://launch/<app id>/x/<index> (any word in the middle), Steam starts that option without
its dialog. The index counts, from 0 and in key order, only the options for the platform the game runs on:
Linux for a native game, Windows when it runs on Proton (set to a compatibility tool for this game, or
with no Linux option at all). Options for another platform, or only for a beta branch, aren't counted.
They come from appcache/appinfo.vdf (config → launch).

Usage: steam_launch_options.py <app id>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Run with -I, which leaves its own folder out
from launch_options import COMPAT_KEYS, CONFIG_VDF, get_value, path_in, read_vdf  # noqa: E402
from steam_appinfo import apps  # noqa: E402


def forced_proton(appid):
    """Set to a compatibility tool for this game itself (not just the default for every game)"""
    try:
        entry = path_in(read_vdf(CONFIG_VDF), COMPAT_KEYS + [appid])
        return bool(entry and get_value(entry, "name"))
    except Exception:
        return False


def options(appid):
    try:
        launch = apps([int(appid)]).get(int(appid), {}).get("config", {}).get("launch", {})
    except (OSError, ValueError):
        return []
    entries = [launch[k] for k in sorted(launch, key=lambda k: int(k) if k.isdigit() else 1 << 30) if isinstance(launch[k], dict)]
    entries = [e for e in entries if not (e.get("config") or {}).get("betakey")]
    def oslist(e):
        return str((e.get("config") or {}).get("oslist", ""))
    has_linux = any("linux" in oslist(e) for e in entries)
    platform = "windows" if forced_proton(appid) or not has_linux else "linux"
    mine = [e for e in entries if not oslist(e) or platform in oslist(e)]
    if len(mine) < 2:
        return []
    out = []
    for i, e in enumerate(mine):
        label = (e.get("description_loc") or {}).get("english") or e.get("description") or ""
        out.append({"index": i, "label": label, "detail": (e.get("arguments") or os.path.basename(e.get("executable", ""))).strip()})
    return out


if __name__ == "__main__":
    print(json.dumps(options(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else []))
