#!/usr/bin/env python3
"""Lists a game's clips for the launcher's Clips page, newest first.

Usage: list_clips.py <clips folder of the game> <cache dir>
Prints one line per clip, tab-separated:
  <modified, s since epoch>  <duration s>  <width>  <height>  <bytes>  <thumbnail path>  <clip path>
Each clip's details (ffprobe) and thumbnail (a frame ~1 s in, 480 px wide, ffmpeg) are made once and
kept in the cache dir, named by a hash of the path, size and time, so a clip that changes gets new ones.
New clips are worked on a few at a time. Afterwards, cache files no clip of any game matches any more
(deleted or moved clips) are removed, once they're a day old.
"""
import hashlib
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

VIDEO = (".mp4", ".mkv", ".webm", ".mov")


def cache_key(path, st):
    return hashlib.sha1(f"{path}\0{st.st_size}\0{st.st_mtime_ns}".encode()).hexdigest()[:20]


def prune(clips_root, cache):
    """Removes cache files for clips that are gone, from every game's folder in clips_root"""
    live = set()
    try:
        for game in os.scandir(clips_root):
            if game.is_dir():
                for e in os.scandir(game.path):
                    if e.is_file() and e.name.lower().endswith(VIDEO):
                        live.add(cache_key(e.path, e.stat()))
    except OSError:
        return
    old = time.time() - 86400
    for e in os.scandir(cache):
        try:
            if e.name.split(".")[0] not in live and e.stat().st_mtime < old:
                os.remove(e.path)
        except OSError:
            pass


def details(path, st, cache):
    key = cache_key(path, st)
    meta_path = os.path.join(cache, key + ".json")
    thumb = os.path.join(cache, key + ".jpg")
    meta = None
    try:
        with open(meta_path) as f:
            meta = json.load(f)
    except (OSError, ValueError):
        pass
    if meta is None:
        meta = {"duration": 0, "width": 0, "height": 0}
        try:
            out = subprocess.run(
                ["ffprobe", "-v", "error", "-select_streams", "v:0",
                 "-show_entries", "stream=width,height:format=duration", "-of", "json", path],
                capture_output=True, text=True, timeout=15).stdout
            j = json.loads(out or "{}")
            s = (j.get("streams") or [{}])[0]
            meta = {"duration": float(j.get("format", {}).get("duration") or 0),
                    "width": int(s.get("width") or 0), "height": int(s.get("height") or 0)}
            with open(meta_path, "w") as f:
                json.dump(meta, f)
        except (OSError, ValueError, subprocess.SubprocessError):
            pass
    if not os.path.exists(thumb):
        at = "1" if meta["duration"] > 2 else "0"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", at, "-i", path, "-frames:v", "1",
                        "-vf", "scale=480:-2", "-q:v", "4", thumb],
                       capture_output=True, timeout=20)
    return meta, (thumb if os.path.exists(thumb) else "")


def main():
    folder, cache = sys.argv[1], sys.argv[2]
    os.makedirs(cache, exist_ok=True)
    try:
        entries = [e for e in os.scandir(folder) if e.is_file() and e.name.lower().endswith(VIDEO)]
    except OSError:
        return  # No clips for this game yet
    entries.sort(key=lambda e: e.stat().st_mtime, reverse=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda e: (e, e.stat(), details(e.path, e.stat(), cache)), entries))
    for e, st, (meta, thumb) in results:
        print("\t".join([f"{st.st_mtime:.3f}", f"{meta['duration']:.2f}", str(meta["width"]),
                         str(meta["height"]), str(st.st_size), thumb, e.path]), flush=True)
    sys.stdout.close()  # The page has its list; tidying the cache can't hold it up
    prune(os.path.dirname(os.path.normpath(folder)), cache)


if __name__ == "__main__":
    main()
