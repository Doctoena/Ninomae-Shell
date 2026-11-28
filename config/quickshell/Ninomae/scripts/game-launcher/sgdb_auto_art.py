#!/usr/bin/env python3
"""Art for a game added by hand in the launcher: finds it on SteamGridDB by name and downloads the top
cover (600x900), banner (hero) and logo, so it shows like the rest of the library straight away.
Better picks are a click away in Browse art.

Usage: SGDB_KEY=… sgdb_auto_art.py <game name> <dest dir> <file name prefix>
Prints "<grid|hero|logo> <path>" for each one saved; nothing if the game isn't found.
The key comes from the environment, not the arguments (any process can read those with ps).
"""
import json
import os
import sys
import urllib.parse
import urllib.request

API = "https://www.steamgriddb.com/api/v2"
KINDS = {"grid": "grids/game/{id}?dimensions=600x900&limit=1",
         "hero": "heroes/game/{id}?limit=1",
         "logo": "logos/game/{id}?limit=1"}


def get(url, key):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {key}", "User-Agent": "Ninomae-Shell"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read()


def main():
    name, dest, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    key = os.environ.get("SGDB_KEY", "")
    if not key or not name.strip():
        return
    found = json.loads(get(f"{API}/search/autocomplete/{urllib.parse.quote(name)}", key))
    if not found.get("success") or not found.get("data"):
        return
    game_id = found["data"][0]["id"]
    os.makedirs(dest, exist_ok=True)
    for kind, path in KINDS.items():
        try:
            items = json.loads(get(f"{API}/{path.format(id=game_id)}", key)).get("data") or []
            if not items:
                continue
            url = items[0]["url"]
            ext = os.path.splitext(urllib.parse.urlparse(url).path)[1].lower() or ".png"
            if ext not in (".png", ".jpg", ".jpeg", ".webp"):
                continue
            out = os.path.join(dest, f"{prefix}_sgdb_{kind}_auto{ext}")
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Ninomae-Shell"}), timeout=30) as resp:
                data = resp.read()
            with open(out, "wb") as f:
                f.write(data)
            print(kind, out, flush=True)
        except Exception:  # One kind missing or failing doesn't stop the others
            continue


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
