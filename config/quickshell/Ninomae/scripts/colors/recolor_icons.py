#!/usr/bin/env python3
"""Keeps the icon theme's accent on the wallpaper's colour (run by applycolor.sh after every scheme change).

Ninomae-Icons-purple draws its folders (and a few app/device icons) in one purple, #7e57c2. This writes
the ~535 icons that use it, recoloured, into a small theme of their own, Ninomae-Icons-accent, which
inherits everything else from Ninomae-Icons-purple (left untouched). Only the hue changes, to the
accent's, so the folders keep their lightness and look; a grey wallpaper gives grey folders. GTK, Qt
and Hyprland all use Ninomae-Icons-accent.

It also sets GNOME's accent-color (libadwaita and Flatpak apps) to the closest of its presets.
Nothing is rewritten when the colour hasn't changed. Running apps are told to reload their icons.
"""
import colorsys
import json
import os
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
STATE = os.environ.get("XDG_STATE_HOME", f"{HOME}/.local/state")
COLORS = f"{STATE}/quickshell/user/generated/colors.json"
ICONS = f"{HOME}/.local/share/icons"
SRC = f"{ICONS}/Ninomae-Icons-purple"
DST = f"{ICONS}/Ninomae-Icons-accent"
PURPLE = "#7e57c2"
# The source purple's saturation and lightness, kept so the folders keep their look
SAT, LIGHT = 0.47, 0.55
# GNOME's accent presets, by hue (slate: for colourless wallpapers)
PRESETS = [("red", 0), ("orange", 28), ("yellow", 50), ("green", 130), ("teal", 180), ("blue", 215),
           ("purple", 270), ("pink", 325), ("red", 360)]


def hex_to_hls(c):
    r, g, b = (int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return colorsys.rgb_to_hls(r, g, b)


def target_colour(accent):
    h, _, s = hex_to_hls(accent)
    r, g, b = colorsys.hls_to_rgb(h, LIGHT, min(SAT, s))  # A grey accent stays grey
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255)), h * 360, s


def gnome_accent(hue, sat):
    if sat < 0.15:
        return "slate"
    return min(PRESETS, key=lambda p: abs(p[1] - hue))[0]


def files_with_purple():
    """Relative paths of the source icons that use the purple; found once, then remembered"""
    listing = f"{DST}/.files"
    if os.path.exists(listing):
        with open(listing) as f:
            return f.read().split("\n")
    out = []
    for root, _, names in os.walk(SRC):  # Real folders only: the @2x ones are links to them (see link_like_source)
        for n in names:
            if n.endswith(".svg"):
                p = os.path.join(root, n)
                try:
                    with open(p, errors="ignore") as f:
                        if PURPLE in f.read().lower():
                            out.append(os.path.relpath(p, SRC))
                except OSError:
                    pass
    os.makedirs(DST, exist_ok=True)
    with open(listing, "w") as f:
        f.write("\n".join(out))
    return out


def link_like_source():
    """The source's linked folders (16@2x -> 16, …) as the same links here, not copies"""
    for name in os.listdir(SRC):
        src = f"{SRC}/{name}"
        dst = f"{DST}/{name}"
        if os.path.islink(src) and not os.path.lexists(dst):
            os.symlink(os.readlink(src), dst)


def write_index():
    """The source's index.theme (same folders), renamed, inheriting it for everything not recoloured"""
    with open(f"{SRC}/index.theme") as f:
        lines = f.read().split("\n")
    out = []
    for line in lines:
        if line.startswith("Name="):
            line = "Name=Ninomae Icons (accent)"
        elif line.startswith("Inherits="):
            line = "Inherits=Ninomae-Icons-purple," + line[len("Inherits="):]
        out.append(line)
    if not any(l.startswith("Inherits=") for l in out):
        out.insert(out.index("[Icon Theme]") + 1, "Inherits=Ninomae-Icons-purple")
    with open(f"{DST}/index.theme", "w") as f:
        f.write("\n".join(out))


def gsettings(key, value):
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", key, value],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    if not os.path.isdir(SRC):
        return 0
    try:
        with open(COLORS) as f:
            accent = json.load(f)["primary"]
    except (OSError, ValueError, KeyError):
        return 0
    colour, hue, sat = target_colour(accent)
    if shutil.which("gsettings"):  # Every run (also at login, where Hyprland's startup runs this)
        gsettings("accent-color", gnome_accent(hue, sat))
    stamp = f"{DST}/.colour"
    first = not os.path.exists(f"{DST}/index.theme")
    if not first and os.path.exists(stamp) and open(stamp).read() == colour:
        return 0  # Same colour as last time: the icons are already right
    for rel in files_with_purple():
        if not rel:
            continue
        src, dst = f"{SRC}/{rel}", f"{DST}/{rel}"
        try:
            with open(src, errors="ignore") as f:
                svg = f.read()
        except OSError:
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst + ".tmp", "w") as f:
            f.write(svg.replace(PURPLE, colour).replace(PURPLE.upper(), colour))
        os.replace(dst + ".tmp", dst)
    link_like_source()
    write_index()
    with open(stamp, "w") as f:
        f.write(colour)
    # Running GTK apps reload icons when the theme name changes: a quick switch away and back
    if shutil.which("gsettings"):
        gsettings("icon-theme", "Ninomae-Icons-purple")
        gsettings("icon-theme", "Ninomae-Icons-accent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
