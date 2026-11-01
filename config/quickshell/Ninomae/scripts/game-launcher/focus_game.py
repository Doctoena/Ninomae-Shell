#!/usr/bin/env python3
"""Brings a running Steam game's window to the front (the launcher's Playing button): the window of one of
its processes (scripts/clips/game_pids.py), else Steam's steam_app_<id> class. Exits 1 when there's none.

Usage: focus_game.py <steam app id>
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "clips"))
from game_pids import game_pids  # noqa: E402


def main(appid):
    pids = set(game_pids(appid))
    try:
        clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5).stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 1
    window = next((c for c in clients if c.get("pid") in pids), None) \
        or next((c for c in clients if c.get("class") == f"steam_app_{appid}"), None)
    if not window:
        return 1
    subprocess.run(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{window["address"]}" }})'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 2)
