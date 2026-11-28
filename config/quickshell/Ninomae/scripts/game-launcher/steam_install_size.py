#!/usr/bin/env python3
"""Install size of a Steam game that isn't installed, from Steam's own app cache (no network).

  steam_install_size.py <appid>   → JSON: {"size": bytes on disk, "download": bytes to download} or {}

Reads appcache/appinfo.vdf (binary KeyValues, format 28/29) and adds up the public manifests of the
depots Steam would install: the Linux ones if the game has any, otherwise Windows (Proton), skipping
DLC, other-language and shared-redistributable depots. Close to what Steam's install dialog shows.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))) # Also when run with -I
from steam_appinfo import apps

def install_size(appid):
    depots = apps([appid]).get(appid, {}).get("depots") or {}
    counted = [] # (oslist, public manifest) of the depots a normal install would get
    for key, d in depots.items():
        if not key.isdigit() or not isinstance(d, dict) or d.get("dlcappid") or d.get("sharedinstall"):
            continue
        public = (d.get("manifests") or {}).get("public")
        cfg = d.get("config") or {}
        if not isinstance(public, dict) or "size" not in public or cfg.get("lowviolence"):
            continue
        if cfg.get("language", "") in ("", "english"):
            counted.append((cfg.get("oslist", ""), public))
    # Native Linux files if the game has any, otherwise the Windows ones Proton would run
    target = "linux" if any("linux" in oslist for oslist, _ in counted) else "windows"
    use = [m for oslist, m in counted if not oslist or target in oslist]
    if not use:
        return {}
    return {"size": sum(int(m.get("size", 0)) for m in use),
            "download": sum(int(m.get("download", 0)) for m in use)}

if __name__ == "__main__":
    try:
        print(json.dumps(install_size(int(sys.argv[1]))))
    except Exception:
        print("{}")
