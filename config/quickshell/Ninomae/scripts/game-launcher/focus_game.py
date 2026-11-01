#!/usr/bin/env python3
"""Brings a running game's window to the front (the launcher's Playing button): the window of one of its
processes (scripts/clips/game_pids.py, with the same kind:key matchers), else for a Steam game Steam's
steam_app_<id> class. Exits 1 when there's none.

Usage: focus_game.py <kind:key> […]     e.g. steam:108600, or lutris:Hytale flatpak:com.hypixel.HytaleLauncher
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "clips"))
from game_pids import game_pids  # noqa: E402


def main(matchers):
    pids = set(game_pids(matchers))
    try:
        clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5).stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 1
    steam_classes = {f"steam_app_{m[6:]}" for m in matchers if m.startswith("steam:")}
    window = next((c for c in clients if c.get("pid") in pids), None) \
        or next((c for c in clients if c.get("class") in steam_classes), None)
    if not window:
        return 1
    subprocess.run(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{window["address"]}" }})'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    args = [a if ":" in a else f"steam:{a}" for a in sys.argv[1:]]
    sys.exit(main(args) if args else 2)
