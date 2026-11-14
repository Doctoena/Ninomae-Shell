#!/usr/bin/env python3
"""The whole library's captures, for the launcher's stats page: the screenshots the shell saved
(<Pictures>/Screenshots/Games/<game>/, as find_screenshots.py names them) and the gameplay clips
(<clips folder>/<game>/).

Usage: library_captures.py <clips folder> <clip thumbnail cache>
Prints one JSON object:
  {"shots", "shotBytes", "clips", "clipBytes", "latest": [{"kind": "shot"|"clip", "time", "image", "full",
   "game": its folder's name, the game's name made safe (GameClips.safeName)}]}
latest: the newest few of both, each with a small picture to show ("image": the shot, or the frame the Clips
page made for a clip, list_clips.py's cache key; "" when there's none yet) and a big one ("full": the shot,
or that same frame).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I leaves the script's own folder out
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "clips"))
from find_screenshots import EXTENSIONS as SHOTS, games_dir
from list_clips import cache_key, thumb_path  # noqa: E402 (the thumbnails are list_clips.py's)
VIDEO = (".mp4", ".mkv", ".webm", ".mov")
LATEST = 5  # The stats page's Captures card: the newest large, four under it


def clip_thumb(path, st, cache):
    """list_clips.py's thumbnail for this clip, if it made one"""
    thumb = thumb_path(cache, cache_key(path, st))
    return thumb if os.path.exists(thumb) else ""


def per_game(root, extensions, kind, out, found):
    """The files in each game's folder under root: counted into out[kind + "s"] and out[kind + "Bytes"], and
    listed in found as (time, kind, path, the folder's name, stat)"""
    try:
        games = [g for g in os.scandir(root) if g.is_dir()] if root else []
    except OSError:
        return
    for game in games:
        try:
            entries = list(os.scandir(game.path))
        except OSError:
            continue
        for e in entries:
            if e.name.lower().endswith(extensions) and e.is_file():
                st = e.stat()
                out[kind + "s"] += 1
                out[kind + "Bytes"] += st.st_size
                found.append((st.st_mtime, kind, e.path, game.name, st))


def main():
    clips_root, cache = (sys.argv[1:3] + ["", ""])[:2]
    out = {"shots": 0, "shotBytes": 0, "clips": 0, "clipBytes": 0}
    found = []
    per_game(games_dir(), SHOTS, "shot", out, found)
    per_game(clips_root, VIDEO, "clip", out, found)
    found.sort(key=lambda f: f[0], reverse=True)
    latest = []
    for time, kind, path, game, st in found[:LATEST]:
        image = path if kind == "shot" else clip_thumb(path, st, cache)
        latest.append({"kind": kind, "time": time, "image": image, "full": image, "game": game})
    out["latest"] = latest
    print(json.dumps(out))


if __name__ == "__main__":
    main()
