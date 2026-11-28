#!/usr/bin/env python3
"""Keyboard layouts for Settings → Input and the key names the Keybinds page shows.

  xkb_layouts.py list                    → [{"layout", "name", "variants": [{"variant", "name"}]}] (JSON)
  xkb_layouts.py labels LAYOUT [VARIANT] → {"<xkb keycode>": "<what's printed on that key>"} (JSON)

`labels` covers the punctuation keys the shortcuts use. Away from US layouts those are bound by
position (hypr/hyprland/keymap.lua), so Hyprland lists them as code:NN: this names them as the layout
does (on German, code:47 is "Ö"). Needs xkbcomp. Without it, or for an unknown layout, it prints {}.
"""
import json
import re
import subprocess
import sys
import unicodedata
from functools import cache

RULES = "/usr/share/X11/xkb/rules/evdev.lst"
COMPOSE = "/usr/share/X11/locale/en_US.UTF-8/Compose"
# The keys keymap.lua binds by position: - = [ ] ; ' , . / on a US keyboard
CODES = {"AE11": 20, "AE12": 21, "AD11": 34, "AD12": 35, "AC10": 47, "AC11": 48, "AB08": 59, "AB09": 60, "AB10": 61}
NAMED = { # Keysym → what's printed on the key, for those whose name doesn't say
    "minus": "-", "equal": "=", "bracketleft": "[", "bracketright": "]", "semicolon": ";",
    "apostrophe": "'", "comma": ",", "period": ".", "slash": "/", "backslash": "\\", "grave": "`",
    "plus": "+", "less": "<", "greater": ">", "numbersign": "#", "asterisk": "*", "dollar": "$",
    "parenleft": "(", "parenright": ")", "exclam": "!", "colon": ":", "question": "?", "quotedbl": '"',
    "ampersand": "&", "underscore": "_", "asciicircum": "^", "circumflex": "^", "asciitilde": "~",
    "tilde": "~", "percent": "%", "at": "@", "bar": "|", "section": "§", "acute": "´", "diaeresis": "¨",
    "cedilla": "¸", "degree": "°", "abovering": "°", "ssharp": "ß",
}


def layouts():
    out, section, by_code = [], None, {}
    with open(RULES, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("!"):
                section = line[1:].strip()
                continue
            if not line.strip():
                continue
            if section == "layout":
                code, name = line.split(None, 1)
                entry = {"layout": code, "name": name.strip(), "variants": []}
                by_code[code] = entry
                out.append(entry)
            elif section == "variant":
                m = re.match(r"\s*(\S+)\s+(\S+):\s*(.+)", line)
                if m and m.group(2) in by_code:
                    name = m.group(3).strip()
                    short = re.fullmatch(r"[^(]+\((.+)\)", name) # "German (no dead keys)" → "No dead keys"
                    name = short.group(1) if short else name
                    by_code[m.group(2)]["variants"].append({"variant": m.group(1), "name": name[:1].upper() + name[1:]})
    out.sort(key=lambda e: e["name"].lower())
    return out


@cache # Only read when a key needs it (most layouts never do)
def compose_chars():
    chars = {}
    try:
        with open(COMPOSE, encoding="utf-8") as f:
            for line in f:
                m = re.search(r':\s*"([^"]+)"\s+(\w+)', line)
                if m:
                    chars.setdefault(m.group(2), m.group(1))
    except OSError:
        pass
    return chars


def label(sym):
    sym = sym.removeprefix("dead_")
    if len(sym) == 1:
        return sym.upper()
    text = NAMED.get(sym) or compose_chars().get(sym)
    if not text and "_" in sym: # Cyrillic_zhe → ж, Greek_alpha → α
        script, _, letter = sym.partition("_")
        for case in ("SMALL", "CAPITAL"):
            try:
                text = unicodedata.lookup(f"{script} {case} LETTER {letter}".upper())
                break
            except KeyError:
                pass
    if not text:
        return sym
    return text.upper() if len(text.upper()) == 1 else text # ß stays ß, not SS


def labels(layout, variant):
    if not re.fullmatch(r"[\w-]+", layout) or (variant and not re.fullmatch(r"[\w-]+", variant)):
        return {}
    symbols = f"pc+{layout}({variant})+inet(evdev)" if variant else f"pc+{layout}+inet(evdev)"
    keymap = ('xkb_keymap { xkb_keycodes { include "evdev" }; xkb_types { include "complete" }; '
              f'xkb_compat {{ include "complete" }}; xkb_symbols {{ include "{symbols}" }}; }};')
    try:
        text = subprocess.run(["xkbcomp", "-w0", "-xkb", "-", "-"], input=keymap, capture_output=True,
                              text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return {}
    out = {}
    # key <AC10> { [ odiaeresis, Odiaeresis ] }; also written as symbols[Group1]= [ ... ] over several lines
    for name, body in re.findall(r"key <(\w+)>\s*\{(.*?)\};", text, re.S):
        if name in CODES:
            m = re.search(r"(?:^|=)\s*\[\s*([^,\]\s]+)", body.strip())
            if m:
                out[str(CODES[name])] = label(m.group(1))
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["list"]:
        print(json.dumps(layouts()))
    elif args[:1] == ["labels"] and len(args) >= 2:
        print(json.dumps(labels(args[1], args[2] if len(args) > 2 else "")))
    else:
        sys.exit(__doc__)
