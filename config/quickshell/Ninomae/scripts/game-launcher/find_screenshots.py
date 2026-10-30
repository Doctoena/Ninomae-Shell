#!/usr/bin/env python3
"""Lists a game's screenshots for the launcher's gallery, newest first, at most 300:
"<mtime>\t<width>\t<height>\t<path>" per line, after a first line "folder\t<path>": where the game's
screenshots go, for the gallery's Open folder button even with none yet ("" when there's nowhere: a
non-Steam game without a screenshots folder). For a Steam game that's Steam's F12 folder, which may not
exist yet (the button makes it). The time lets the gallery merge them with the game's
Immich album and group them by day; the size lays them out at their own shape (0 when unreadable).

Usage: find_screenshots.py <steam app id or ""> <game folder or ""> <flatpak id or "">
  - Steam: what F12 saved, in every Steam account's userdata/<account>/760/remote/<app id>/screenshots
  - The game's own folders named "screenshots" (any case) in its install folder, and for a Flatpak
    game in its sandboxed data (~/.var/app/<id>), where e.g. Minecraft-style games keep them
Sizes come from the files' headers (PNG, JPEG, WebP, BMP), so nothing is decoded.
"""
import glob
import os
import struct
import sys

EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")
MAX_DEPTH = 7
LIMIT = 300


def image_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(32)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                return struct.unpack(">II", head[16:24])
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                kind = head[12:16]
                if kind == b"VP8X":
                    return (int.from_bytes(head[24:27], "little") + 1, int.from_bytes(head[27:30], "little") + 1)
                if kind == b"VP8L":
                    bits = int.from_bytes(head[21:25], "little")
                    return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
                if kind == b"VP8 ":
                    w, h = struct.unpack("<HH", head[26:30])
                    return (w & 0x3FFF, h & 0x3FFF)
            if head[:2] == b"BM":
                w, h = struct.unpack("<ii", head[18:26])
                return (w, abs(h))
            if head[:2] == b"\xff\xd8":  # JPEG: walk the segments to the frame header (SOFn)
                f.seek(2)
                while True:
                    marker = f.read(2)
                    if len(marker) < 2 or marker[0] != 0xFF:
                        break
                    if marker[1] in (0xD8, 0x01) or 0xD0 <= marker[1] <= 0xD7:
                        continue
                    length = struct.unpack(">H", f.read(2))[0]
                    if 0xC0 <= marker[1] <= 0xCF and marker[1] not in (0xC4, 0xC8, 0xCC):
                        h, w = struct.unpack(">xHH", f.read(5))
                        return (w, h)
                    f.seek(length - 2, 1)
    except (OSError, struct.error):
        pass
    return (0, 0)


def screenshot_dirs(root):
    """Folders named "screenshots" (any case) under root, at most MAX_DEPTH deep, not in caches."""
    base = root.rstrip("/").count("/")
    for path, dirs, _ in os.walk(root):
        depth = path.count("/") - base
        dirs[:] = [d for d in dirs if d.lower() != "cache"] if depth < MAX_DEPTH else []
        for d in dirs:
            if d.lower() == "screenshots":
                yield os.path.join(path, d)


def main():
    appid, game_dir, flatpak_id = (sys.argv[1:] + ["", "", ""])[:3]
    dirs = []
    if appid:
        dirs += [d for d in glob.glob(os.path.expanduser(f"~/.local/share/Steam/userdata/*/760/remote/{appid}/screenshots")) if os.path.isdir(d)]
    roots = [game_dir] if game_dir and os.path.isdir(game_dir) else []
    if flatpak_id and os.path.isdir(os.path.expanduser(f"~/.var/app/{flatpak_id}")):
        roots.append(os.path.expanduser(f"~/.var/app/{flatpak_id}"))
    for root in roots:
        dirs += screenshot_dirs(root)

    # Where they go: one that exists, else Steam's for the account used last (its userdata folder is
    # the most recently changed one)
    folder = dirs[0] if dirs else ""
    if not folder and appid:
        accounts = [a for a in glob.glob(os.path.expanduser("~/.local/share/Steam/userdata/*")) if os.path.basename(a).isdigit()]
        if accounts:
            account = max(accounts, key=os.path.getmtime)
            folder = os.path.join(account, "760", "remote", appid, "screenshots")
    print(f"folder\t{folder}")

    found = []
    for d in dict.fromkeys(dirs):
        try:
            entries = os.scandir(d)
        except OSError:
            continue
        with entries:  # Not into thumbnails/ subfolders: Steam keeps a small copy of each screenshot there
            for e in entries:
                if e.name.lower().endswith(EXTENSIONS) and e.is_file():
                    found.append((e.stat().st_mtime, e.path))
    found.sort(reverse=True)
    for mtime, path in found[:LIMIT]:
        w, h = image_size(path)
        print(f"{mtime}\t{w}\t{h}\t{path}")


if __name__ == "__main__":
    main()
