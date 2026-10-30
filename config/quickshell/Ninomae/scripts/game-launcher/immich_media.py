#!/usr/bin/env python3
"""Fetches Immich photos for the launcher's Screenshots panel into a private cache, so the panel shows
them from disk: an Image can't send the key in a header, and a key in the URL ends up in the access
logs of whatever sits in front of the server (Cloudflare, a reverse proxy). Prints
"<asset id>\t<path>" per photo it has, as each is ready; ones already fetched print at once.

Usage: IMMICH_API_KEY=… immich_media.py <server url> <cache dir> <asset id>...
  One size for the grid and the viewer: Immich's "preview" (~1440 px, JPEG). Its "thumbnail" is WebP,
  which Qt only reads with qt6-qtimageformats installed. Kept in <cache dir>/immich (only you can read
  it); a copy not shown for CACHE_DAYS is deleted. Needs the key's asset.view permission
"""
import os
import re
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
CACHE_DAYS = 30
EXTENSIONS = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


def prune(folder):
    """Copies not shown for CACHE_DAYS (each is touched when shown), and half-written ones."""
    cutoff = time.time() - CACHE_DAYS * 86400
    for name in os.listdir(folder):
        path = os.path.join(folder, name)
        try:
            if os.path.getmtime(path) < cutoff or (name.endswith(".tmp") and os.path.getmtime(path) < time.time() - 3600):
                os.remove(path)
        except OSError:
            pass


def main():
    base, cache_dir, ids = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3:]
    key = os.environ.get("IMMICH_API_KEY", "")
    if not key:
        return
    folder = os.path.join(cache_dir, "immich")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    os.chmod(folder, 0o700)
    prune(folder)
    have = {name.split(".")[0]: os.path.join(folder, name) for name in os.listdir(folder) if not name.endswith(".tmp")}

    def fetch(asset):
        if not UUID.match(asset):  # Only ids from the server's answer get here, but they name files
            return
        path = have.get(asset)
        if path:
            os.utime(path)  # Shown: kept another CACHE_DAYS
        else:
            req = urllib.request.Request(f"{base}/api/assets/{asset}/thumbnail?size=preview",
                                         headers={"x-api-key": key, "User-Agent": "Ninomae-Shell"})
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    data = resp.read()
                    ext = EXTENSIONS.get(resp.headers.get_content_type(), ".jpg")
            except Exception:
                return
            path = os.path.join(folder, asset + ext)
            tmp = f"{path}.{os.getpid()}.tmp"
            with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as f:
                f.write(data)
            os.replace(tmp, path)
        print(f"{asset}\t{path}", flush=True)

    with ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(fetch, ids))


if __name__ == "__main__":
    main()
