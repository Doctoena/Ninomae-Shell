#!/usr/bin/env python3
"""GE-Proton for Settings → Games: what's installed, the latest release, installing and removing.

  proton_ge.py list            {"installed": [{"name", "bytes", "usedBy": [app id or "default"]}], "steamRunning"}
  proton_ge.py latest          {"tag", "published", "bytes"} from GitHub, or {"error"}
  proton_ge.py install <tag>   lines "progress <0–1>", then "done <tag>" or "error <message>"
  proton_ge.py remove <name>   "done" or "error <message>"
  proton_ge.py restart-steam   closes Steam and starts it again in the tray (it only looks for new versions then)

Versions live in Steam's compatibilitytools.d, one folder each, the way ProtonUp-Qt installs them. A
download is checked against the release's sha512sum before it's unpacked. "usedBy" is from Steam's
config.vdf (CompatToolMapping): the games set to that version, "default" when it's the one for all games.
"""
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Run with -I, which leaves its own folder out
from launch_options import (COMPAT_KEYS, CONFIG_VDF, STEAM, close_steam, get_value, path_in,  # noqa: E402
                            read_vdf, start_steam, steam_running)

TOOLS = os.path.join(STEAM, "compatibilitytools.d")
API = "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases"
# A version's folder: GE-Proton11-11 (as installed here), or with its build's arch as the release unpacks
# and other tools leave it (GE-Proton11-11-x86_64)
NAME = re.compile(r"^(GE-Proton(\d+)-(\d+))(-[A-Za-z0-9_]+)?$")
ARCH = platform.machine()  # x86_64; GE-Proton 11 also has aarch64 builds
HEADERS = {"Accept": "application/vnd.github+json", "User-Agent": "Ninomae-Shell"}


def get(url, timeout=20):
    return urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=timeout)


def folder_size(path):
    """Bytes in a folder: du (~10× faster on Proton's thousands of files), else a walk"""
    try:
        return int(subprocess.run(["du", "-sb", path], capture_output=True, text=True, timeout=10).stdout.split()[0])
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        pass
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


def tool_names(folder):
    """The names Steam knows a version by: those in its compatibilitytool.vdf (GE-Proton11-11-x86_64), and
    the folder's own"""
    names = {os.path.basename(folder)}
    try:
        for name, _ in path_in(read_vdf(os.path.join(folder, "compatibilitytool.vdf")),
                               ["compatibilitytools", "compat_tools"]) or []:
            names.add(name)
    except Exception:
        pass
    return names


def used_by(folder, used):
    return sorted({app for name in tool_names(folder) for app in used.get(name, [])})


def usage():
    """{tool name: [app ids]} from CompatToolMapping ("0" is the default for every game)"""
    out = {}
    try:
        mapping = path_in(read_vdf(CONFIG_VDF), COMPAT_KEYS) or []
    except Exception:
        return out
    for appid, entry in mapping:
        name = get_value(entry, "name") if isinstance(entry, list) else None
        if name:
            out.setdefault(name, []).append("default" if appid == "0" else appid)
    return out


def version_key(name):
    m = NAME.match(name)
    return (int(m.group(2)), int(m.group(3))) if m else (0, 0)


def installed_folder(tag):
    """The folder a version is in, either way it's named, or None"""
    for d in (tag, f"{tag}-{ARCH}"):
        if os.path.isdir(os.path.join(TOOLS, d)):
            return d
    return None


def cmd_list():
    used = usage()
    installed = []
    if os.path.isdir(TOOLS):
        for d in os.listdir(TOOLS):
            if NAME.match(d) and os.path.isdir(os.path.join(TOOLS, d)):
                path = os.path.join(TOOLS, d)
                installed.append({"name": d, "version": NAME.match(d).group(1), "bytes": folder_size(path),
                                  "usedBy": used_by(path, used)})
    installed.sort(key=lambda v: version_key(v["name"]), reverse=True)
    print(json.dumps({"installed": installed, "steamRunning": steam_running()}))


def release(tag=None):
    with get(f"{API}/tags/{tag}" if tag else f"{API}/latest") as r:
        data = json.load(r)
    tag = data["tag_name"]
    assets = {a["name"]: a for a in data.get("assets", [])}
    # This computer's build (GE-Proton11-11-x86_64.tar.gz), or the one build older releases have
    base = next((b for b in (f"{tag}-{ARCH}", tag) if f"{b}.tar.gz" in assets), None)
    if not base:
        raise RuntimeError(f"the release has no download for this computer ({ARCH})")
    return data, assets[f"{base}.tar.gz"], assets.get(f"{base}.sha512sum")


def cmd_latest():
    try:
        data, tarball, _ = release()
        print(json.dumps({"tag": data["tag_name"], "published": data.get("published_at", ""),
                          "bytes": tarball.get("size", 0)}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))


def cmd_install(tag):
    # Settings closing mid-download stops this with SIGTERM: as an exit, so the half download is cleaned up
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    m = NAME.match(tag)
    if not m or m.group(4):
        print("error Not a GE-Proton version", flush=True)
        return 1
    if installed_folder(tag):  # Already here, however it was installed
        print(f"done {tag}", flush=True)
        return 0
    os.makedirs(TOOLS, exist_ok=True)
    for d in os.listdir(TOOLS):  # Left by one that was killed outright
        if d.startswith(".ninomae-"):
            shutil.rmtree(os.path.join(TOOLS, d), ignore_errors=True)
    try:
        _, tarball, checksum = release(tag)
        expected = None
        if checksum:
            with get(checksum["browser_download_url"]) as r:
                expected = r.read().decode().split()[0].lower()
        # Downloaded next to its destination (same drive, a few hundred MB), then unpacked and moved in
        with tempfile.TemporaryDirectory(dir=TOOLS, prefix=".ninomae-") as tmp:
            path = os.path.join(tmp, tarball["name"])
            digest = hashlib.sha512()
            with get(tarball["browser_download_url"], timeout=60) as r, open(path, "wb") as f:
                total = int(r.headers.get("Content-Length") or tarball.get("size") or 0)
                done, last = 0, -1.0
                while chunk := r.read(1 << 20):
                    f.write(chunk)
                    digest.update(chunk)
                    done += len(chunk)
                    if total and done / total - last >= 0.01:
                        last = done / total
                        print(f"progress {last * 0.9:.3f}", flush=True)  # The last 10 %: unpacking
            if expected and digest.hexdigest() != expected:
                raise RuntimeError("the download was damaged (checksum didn't match), try again")
            with tarfile.open(path) as t:
                t.extractall(tmp, filter="data")
            os.remove(path)
            # Its one folder (GE-Proton11-11-x86_64/), installed as the version's name
            unpacked = [d for d in os.listdir(tmp) if os.path.isdir(os.path.join(tmp, d))]
            if len(unpacked) != 1 or not os.path.exists(os.path.join(tmp, unpacked[0], "compatibilitytool.vdf")):
                raise RuntimeError("the download isn't a GE-Proton version")
            os.rename(os.path.join(tmp, unpacked[0]), os.path.join(TOOLS, tag))
        print("progress 1", flush=True)
        print(f"done {tag}", flush=True)
        return 0
    except Exception as e:
        print(f"error {e}", flush=True)
        return 1


def cmd_remove(name):
    path = os.path.join(TOOLS, name)
    if not NAME.match(name) or not os.path.isdir(path):
        print("error Not an installed GE-Proton version")
        return 1
    if used_by(path, usage()):
        print("error Games are still set to use it")
        return 1
    shutil.rmtree(path)
    print("done")
    return 0


def cmd_restart_steam():
    if steam_running() and not close_steam():
        print("error Steam won't close")
        return 1
    start_steam()
    print("done")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd == "list":
        cmd_list()
    elif cmd == "latest":
        cmd_latest()
    elif cmd == "install" and len(args) == 2:
        sys.exit(cmd_install(args[1]))
    elif cmd == "remove" and len(args) == 2:
        sys.exit(cmd_remove(args[1]))
    elif cmd == "restart-steam":
        sys.exit(cmd_restart_steam())
    else:
        print(__doc__)
        sys.exit(2)
