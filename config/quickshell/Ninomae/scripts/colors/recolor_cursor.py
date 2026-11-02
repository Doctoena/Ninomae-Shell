#!/usr/bin/env python3
"""Keeps the cursor on the wallpaper's accent (run by applycolor.sh after every scheme change, and at login).

The Rosé Pine cursor is a dark body (#191724) with a light outline (#e0def4). This writes it recoloured
into one theme, Ninomae-Cursor-accent, in both formats: Hyprland's own (hyprcursor: SVGs zipped in .hlc
files) and the XCursor one (pixels) that X11 apps such as Steam and games use. The body keeps its
darkness and takes the accent's hue; the outline becomes the accent itself. A grey wallpaper gives a
grey cursor. Anything not drawn in those two colours (the busy spinner's colours, …) is left alone.

Nothing is rewritten when the colour hasn't changed. The running session switches to it at once
(hyprctl setcursor, GNOME's cursor-theme); env.lua and execs.lua pick it at login once it exists.
"""
import colorsys
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import zipfile

HOME = os.path.expanduser("~")
STATE = os.environ.get("XDG_STATE_HOME", f"{HOME}/.local/state")
COLORS = f"{STATE}/quickshell/user/generated/colors.json"
NAME = "Ninomae-Cursor-accent"
DST = f"{HOME}/.local/share/icons/{NAME}"
SEARCH = [f"{HOME}/.local/share/icons", f"{HOME}/.icons", "/usr/share/icons"]
HYPR_SRC, X_SRC = "rose-pine-hyprcursor", "BreezeX-RosePine-Linux"
SIZE = "24"
DARK, LIGHT = (0x19, 0x17, 0x24), (0xe0, 0xde, 0xf4)


def find(theme):
    return next((f"{d}/{theme}" for d in SEARCH if os.path.isdir(f"{d}/{theme}")), None)


def hexrgb(c):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def hexstr(rgb):
    return "#%02x%02x%02x" % rgb


def colours(accent):
    """(body, outline) for an accent: the body is the dark keeping its lightness, in the accent's hue
    (no more saturated than the accent, so grey stays grey)"""
    h, _, s = colorsys.rgb_to_hls(*(v / 255 for v in hexrgb(accent)))
    dh, dl, ds = colorsys.rgb_to_hls(*(v / 255 for v in DARK))
    body = tuple(round(v * 255) for v in colorsys.hls_to_rgb(h, dl, min(ds, s)))
    return body, hexrgb(accent)


# ── Hyprcursor: the SVGs inside each .hlc (a zip), the two colours swapped by name ──
def recolour_hlc(src, dst, body, outline):
    swaps = {hexstr(DARK): hexstr(body), hexstr(LIGHT): hexstr(outline)}
    out = io.BytesIO()
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item)
            if item.filename.endswith(".svg"):
                text = data.decode(errors="replace")
                for old, new in swaps.items():
                    text = text.replace(old, new).replace(old.upper(), new)
                data = text.encode()
            zout.writestr(item, data)
    with open(dst, "wb") as f:
        f.write(out.getvalue())


def write_hyprcursor(src, body, outline):
    with open(f"{src}/manifest.hl") as f:
        manifest = f.read()
    folder = next((l.split("=", 1)[1].strip() for l in manifest.splitlines()
                   if l.strip().startswith("cursors_directory")), "hyprcursors")
    os.makedirs(f"{DST}/{folder}", exist_ok=True)
    for name in os.listdir(f"{src}/{folder}"):
        if name.endswith(".hlc"):
            recolour_hlc(f"{src}/{folder}/{name}", f"{DST}/{folder}/{name}", body, outline)
    lines = [f"name = {NAME}" if l.strip().startswith("name") else l for l in manifest.splitlines()]
    with open(f"{DST}/manifest.hl", "w") as f:
        f.write("\n".join(lines) + "\n")


# ── XCursor: each pixel on the dark-to-light line (the body, the outline, the edges between) is moved to
# the same place on the new body-to-outline line; others are left as they are ──
def pixel_mapper(body, outline):
    span = [l - d for d, l in zip(DARK, LIGHT)]
    length2 = sum(v * v for v in span)
    cache = {}

    def remap(argb):
        if argb in cache:
            return cache[argb]
        a = argb >> 24
        out = argb
        if a:
            # Premultiplied: back to the real colour first
            rgb = [min(255, ((argb >> sh) & 255) * 255 // a) for sh in (16, 8, 0)]
            t = sum((c - d) * v for c, d, v in zip(rgb, DARK, span)) / length2
            t = min(1.0, max(0.0, t))
            near = [d + v * t for d, v in zip(DARK, span)]
            if sum((c - n) ** 2 for c, n in zip(rgb, near)) < 24 ** 2:
                new = [round((b + (o - b) * t) * a / 255) for b, o in zip(body, outline)]
                out = (a << 24) | (new[0] << 16) | (new[1] << 8) | new[2]
        cache[argb] = out
        return out
    return remap


def recolour_xcursor(data, remap):
    """An XCursor file with its image chunks' pixels remapped (format: "Xcur", a table of chunks, and image
    chunks of a 36-byte header then width × height ARGB words)"""
    if data[:4] != b"Xcur":
        return data
    out = bytearray(data)
    header, _, ntoc = struct.unpack_from("<III", data, 4)
    for i in range(ntoc):
        kind, _, pos = struct.unpack_from("<III", data, header + i * 12)
        if kind != 0xfffd0002:  # Not an image
            continue
        size, _, _, _, width, height = struct.unpack_from("<IIIIII", data, pos)
        start, count = pos + size, width * height
        pixels = struct.unpack_from(f"<{count}I", data, start)
        struct.pack_into(f"<{count}I", out, start, *map(remap, pixels))
    return bytes(out)


def write_xcursor(src, body, outline):
    remap = pixel_mapper(body, outline)
    os.makedirs(f"{DST}/cursors", exist_ok=True)
    for name in os.listdir(f"{src}/cursors"):
        s, d = f"{src}/cursors/{name}", f"{DST}/cursors/{name}"
        if os.path.islink(s):  # Alias names (hashes, other spellings): the same links here
            if not os.path.lexists(d):
                os.symlink(os.readlink(s), d)
            continue
        with open(s, "rb") as f:
            data = recolour_xcursor(f.read(), remap)
        with open(d + ".tmp", "wb") as f:
            f.write(data)
        os.replace(d + ".tmp", d)
    with open(f"{DST}/index.theme", "w") as f:
        f.write(f"[Icon Theme]\nName=Ninomae Cursor (accent)\nComment=Rosé Pine BreezeX in the wallpaper's accent\n"
                f"Inherits={X_SRC}\n")


def apply():
    """The running session onto it: Hyprland (its own windows, and Wayland apps' cursors) and GTK"""
    if shutil.which("hyprctl") and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        subprocess.run(["hyprctl", "setcursor", NAME, SIZE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if shutil.which("gsettings"):
        for theme in (X_SRC, NAME):  # A switch away and back: running apps reload it
            subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    hypr_src, x_src = find(HYPR_SRC), find(X_SRC)
    if not hypr_src or not x_src:
        return 0
    try:
        with open(COLORS) as f:
            accent = json.load(f)["primary"]
    except (OSError, ValueError, KeyError):
        return 0
    body, outline = colours(accent)
    stamp = f"{DST}/.colour"
    key = hexstr(body) + hexstr(outline)
    if os.path.exists(f"{DST}/manifest.hl") and os.path.exists(stamp) and open(stamp).read() == key:
        return 0  # Same colours as last time
    write_hyprcursor(hypr_src, body, outline)
    write_xcursor(x_src, body, outline)
    with open(stamp, "w") as f:
        f.write(key)
    apply()
    return 0


if __name__ == "__main__":
    sys.exit(main())
