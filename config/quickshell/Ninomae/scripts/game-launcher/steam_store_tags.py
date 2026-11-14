#!/usr/bin/env python3
"""Adds each Steam game's store tags to the library list: "storeTags", Steam's tag ids, most voted first (12 at most),
from appcache/appinfo.vdf. They pick a game's particle effect (modules/gameLauncher/GameParticles.qml).

  detect_games.sh's JSON list on stdin → the same list, with storeTags, on stdout
  steam_store_tags.py [appinfo.vdf]
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from steam_appinfo import apps, APPINFO  # noqa: E402


def main():
    games = json.load(sys.stdin)
    path = sys.argv[1] if len(sys.argv) > 1 else APPINFO
    ids = [int(g["id"][6:]) for g in games if g.get("id", "").startswith("steam_") and g["id"][6:].isdigit()]
    try:
        info = apps(ids, path) if ids and os.path.exists(path) else {}
    except (OSError, ValueError):
        info = {}
    for g in games:
        if not g.get("id", "").startswith("steam_"):
            continue
        tags = (info.get(int(g["id"][6:]) if g["id"][6:].isdigit() else -1, {}).get("common") or {}).get("store_tags") or {}
        if tags:
            g["storeTags"] = [tags[k] for k in sorted(tags, key=int)][:12]
    json.dump(games, sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
