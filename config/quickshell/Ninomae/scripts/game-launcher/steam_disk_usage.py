#!/usr/bin/env python3
"""Disk space of every installed game: Steam's from its own manifests (no scanning), others' by walking their folders.

  steam_disk_usage.py [games.json]   → JSON: {"<game id>": bytes on disk, ...}

Steam: SizeOnDisk from steamapps/appmanifest_*.acf in every library listed in libraryfolders.vdf, plus the
mods' from steamapps/workshop/appworkshop_<appid>.acf.
Others (games.json: [{"id", "gameDir", "flatpakId"}, ...]): a Flatpak game is its app (user and system
installs) and its ~/.var/app data, where Flatpak launchers like Hytale's download the game; anything else
is its game folder.
"""
import glob, json, os, re, sys

STEAM = os.path.expanduser("~/.local/share/Steam")

def libraries():
    paths = {STEAM}
    try:
        text = open(os.path.join(STEAM, "steamapps", "libraryfolders.vdf"), encoding="utf-8").read()
        paths.update(re.findall(r'"path"\s+"([^"]+)"', text))
    except OSError:
        pass
    return paths

def size_on_disk(manifest):
    """SizeOnDisk from an app or Workshop manifest, 0 if it's missing."""
    try:
        text = open(manifest, encoding="utf-8", errors="replace").read()
    except OSError:
        return 0
    size = re.search(r'"SizeOnDisk"\s+"(\d+)"', text)
    return int(size.group(1)) if size else 0

def disk_usage():
    sizes = {}
    for lib in libraries():
        steamapps = os.path.join(lib, "steamapps")
        for manifest in glob.glob(os.path.join(steamapps, "appmanifest_*.acf")):
            appid = re.search(r"appmanifest_(\d+)\.acf$", manifest).group(1)
            size = size_on_disk(manifest)
            if size > 0:
                sizes["steam_" + appid] = size + size_on_disk(os.path.join(steamapps, "workshop", f"appworkshop_{appid}.acf"))
    return sizes

def folder_size(path, seen):
    """Bytes of the files under path (symlinks not followed), 0 if it's missing. Hardlinked files count once
    (seen: their inodes), like du: Flatpak's deploys share theirs"""
    total, stack = 0, [path]
    while stack:
        try:
            with os.scandir(stack.pop()) as entries:
                for e in entries:
                    if e.is_dir(follow_symlinks=False):
                        stack.append(e.path)
                    elif e.is_file(follow_symlinks=False):
                        st = e.stat(follow_symlinks=False)
                        if st.st_nlink > 1:
                            if (st.st_dev, st.st_ino) in seen:
                                continue
                            seen.add((st.st_dev, st.st_ino))
                        total += st.st_size
        except OSError:
            pass
    return total

def other_usage(games):
    sizes = {}
    for g in games:
        fp, d, seen = g.get("flatpakId") or "", g.get("gameDir") or "", set()
        if fp:
            size = sum(folder_size(os.path.join(root, fp), seen) for root in (
                os.path.expanduser("~/.local/share/flatpak/app"), "/var/lib/flatpak/app", os.path.expanduser("~/.var/app")))
        else:
            size = folder_size(d, seen) if d else 0
        if size > 0:
            sizes[g["id"]] = size
    return sizes

if __name__ == "__main__":
    sizes = disk_usage()
    if len(sys.argv) > 1:
        try:
            sizes.update(other_usage(json.loads(open(sys.argv[1]).read() if os.path.isfile(sys.argv[1]) else sys.argv[1])))
        except (OSError, ValueError):
            pass
    print(json.dumps(sizes))
