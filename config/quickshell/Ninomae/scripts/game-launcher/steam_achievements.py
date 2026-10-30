#!/usr/bin/env python3
"""A Steam game's achievements, from the files the Steam client keeps in appcache/stats (no API key,
works with a private profile, offline), plus how many players have each (Steam's public global
stats, cached a day). Prints JSON for the game launcher, already in display order: unlocked ones
newest first, then locked ones most common first (the easiest to get next):

  {"total": 88, "unlocked": 71, "achievements": [{"id", "name", "description", "hidden", "icon",
   "iconGray", "unlocked", "time", "percent"}]}      percent: -1 when unknown (offline, no data)

Games the Steam client hasn't loaded on this PC (not installed or played here) have no such files:
for those the same list comes from your Steam profile's public achievements page (needs the
profile's game details to be public; cached 6 hours), and "source" says which was used.

Usage: steam_achievements.py <app id> <cache dir> [language]
  - UserGameStatsSchema_<app>.bin: the game's achievements. Stats of type 4 (achievements) hold
    one "bit" per achievement, with its API name and display name/description/icons
  - UserGameStats_<account>_<app>.bin: your progress. Per stat, "data" is a bitfield of unlocked
    achievements and "AchievementTimes" the unlock time (Unix seconds) per bit
Icons are file names on Steam's CDN (see ICON_URL). Each is kept in <cache dir>/achievements/icons
once fetched, and given as a file:// URL from then on; ones not there yet are given as the CDN URL
and fetched in the background after the JSON is printed. Prints {"total": 0} when the game has none.
"""
import glob
import json
import os
import struct
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor

STATS_DIR = os.path.expanduser("~/.local/share/Steam/appcache/stats")
ICON_URL = "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{app}/{file}"
RARITY_URL = "https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid={app}"
RARITY_CACHE_SECONDS = 86400
PROFILE_URL = "https://steamcommunity.com/profiles/{steamid}/stats/{app}/achievements/?xml=1&l={language}"
PROFILE_CACHE_SECONDS = 6 * 3600
LOGIN_USERS = os.path.expanduser("~/.local/share/Steam/config/loginusers.vdf")
# Achievement stats: newer schemas give type_int 4 (or 5, grouped); older ones only the type name
ACHIEVEMENT_TYPE_INTS = {4, 5}
ACHIEVEMENT_TYPE_NAMES = {"ACHIEVEMENTS", "GROUPACHIEVEMENTS", "4", "5"}


def is_achievement_stat(stat):
    return (stat.get("type_int") in ACHIEVEMENT_TYPE_INTS
            or str(stat.get("type", "")).upper() in ACHIEVEMENT_TYPE_NAMES)


def parse_kv(data, i=0):
    """Steam's binary KeyValues: a type byte, a NUL-terminated key, then the value."""
    out = {}
    while i < len(data):
        t = data[i]
        i += 1
        if t in (8, 11):  # End of this object
            return out, i
        j = data.index(b"\0", i)
        key = data[i:j].decode("utf-8", "replace")
        i = j + 1
        if t == 0:
            value, i = parse_kv(data, i)
        elif t == 1:
            j = data.index(b"\0", i)
            value = data[i:j].decode("utf-8", "replace")
            i = j + 1
        elif t in (2, 4, 6):
            value = struct.unpack_from("<i" if t == 2 else "<I", data, i)[0]
            i += 4
        elif t == 3:
            value = struct.unpack_from("<f", data, i)[0]
            i += 4
        elif t in (7, 10):
            value = struct.unpack_from("<Q" if t == 7 else "<q", data, i)[0]
            i += 8
        else:
            raise ValueError(f"unknown KeyValues type {t} at byte {i}")
        out[key] = value
    return out, i


def load(path):
    with open(path, "rb") as f:
        return parse_kv(f.read())[0]


def as_dict(value):
    return value if isinstance(value, dict) else {}  # Empty parts are stored as "" in these files


def rarity(app, cache_dir):
    """API name → % of players who have it. Cached a day; an old copy (or nothing) when offline."""
    cache = os.path.join(cache_dir, "achievements", f"{app}_rarity.json")
    fresh = os.path.isfile(cache) and time.time() - os.path.getmtime(cache) < RARITY_CACHE_SECONDS
    if not fresh:
        try:
            req = urllib.request.Request(RARITY_URL.format(app=app), headers={"User-Agent": "Ninomae-Shell"})
            with urllib.request.urlopen(req, timeout=8) as resp:
                entries = json.load(resp).get("achievementpercentages", {}).get("achievements", [])
            percents = {e["name"]: float(e["percent"]) for e in entries if "name" in e}
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            with open(cache + ".tmp", "w") as f:
                json.dump(percents, f)
            os.replace(cache + ".tmp", cache)
            return percents
        except Exception:
            pass
    try:
        with open(cache) as f:
            return json.load(f)
    except Exception:
        return {}


def cache_icons(app, cache_dir, achievements):
    """Swaps each icon URL for its cached file where there is one. Returns the (url, path) still to fetch."""
    icon_dir = os.path.join(cache_dir, "achievements", "icons", app)
    missing = []
    for a in achievements:
        for key in ("icon", "iconGray"):
            url = a.get(key, "")
            if not url.startswith("http"):
                continue
            path = os.path.join(icon_dir, os.path.basename(url.split("?")[0]))
            if os.path.isfile(path):
                a[key] = "file://" + path
            else:
                missing.append((url, path))
    return missing


def fetch_icons(missing):
    """Downloads icons into the cache, detached: stdout is closed first, so the launcher has its JSON
    (and stops waiting) at once, and the next time the sheet opens they come from disk."""
    if not missing or os.fork() != 0:
        return
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    os.makedirs(os.path.dirname(missing[0][1]), exist_ok=True)

    def fetch(item):
        url, path = item
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Ninomae-Shell"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read()
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
        except Exception:
            pass

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(fetch, dict(missing).items()))  # dict: each URL once
    os._exit(0)


def steam_id():
    """64-bit id of the account last signed in to Steam here (loginusers.vdf, text KeyValues)."""
    try:
        with open(LOGIN_USERS, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return ""
    import re
    accounts = re.findall(r'"(\d{17})"\s*\{([^}]*)\}', text)
    recent = [sid for sid, body in accounts if re.search(r'"MostRecent"\s*"1"', body)]
    return (recent or [sid for sid, _ in accounts] or [""])[0]


def from_profile(app, cache_dir, language):
    """(achievements, error) from the profile's public achievements page, or (None, error)."""
    sid = steam_id()
    if not sid:
        return None, "no-account"
    cache = os.path.join(cache_dir, "achievements", f"{app}_profile.xml")
    data = None
    if os.path.isfile(cache) and time.time() - os.path.getmtime(cache) < PROFILE_CACHE_SECONDS:
        with open(cache, "rb") as f:
            data = f.read()
    else:
        try:
            req = urllib.request.Request(PROFILE_URL.format(steamid=sid, app=app, language=language),
                                         headers={"User-Agent": "Ninomae-Shell"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read()
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            with open(cache + ".tmp", "wb") as f:
                f.write(data)
            os.replace(cache + ".tmp", cache)
        except Exception:
            if os.path.isfile(cache):  # Offline: the last copy
                with open(cache, "rb") as f:
                    data = f.read()
    if data is None:
        return None, "offline"
    try:
        root = ET.fromstring(data)
    except ET.ParseError:
        return None, "unreadable"
    if root.find("error") is not None:  # Private profile, or the game has no stats
        return None, "private" if root.find("privacyState") is not None or b"private" in data.lower() else "none"
    out = []
    for a in root.iter("achievement"):
        unlocked = a.get("closed") == "1"
        text = lambda tag: (a.findtext(tag) or "").strip()
        out.append({
            "id": text("apiname"),
            "name": text("name"),
            "description": text("description"),
            "hidden": False,  # Not in this format; locked hidden ones just show their text
            "icon": text("iconClosed"),    # Colour
            "iconGray": text("iconOpen"),  # Greyed
            "unlocked": unlocked,
            "time": int(text("unlockTimestamp") or 0) if unlocked else 0,
        })
    return out, None


def localised(field, language):
    if isinstance(field, dict):
        return field.get(language) or field.get("english") or next((v for v in field.values() if isinstance(v, str)), "")
    return field if isinstance(field, str) else ""


def main():
    app, cache_dir = sys.argv[1], sys.argv[2]
    language = sys.argv[3] if len(sys.argv) > 3 else "english"
    schema_path = os.path.join(STATS_DIR, f"UserGameStatsSchema_{app}.bin")
    if not os.path.isfile(schema_path):
        achievements, error = from_profile(app, cache_dir, language)
        finish(app, cache_dir, achievements or [], "profile", error)
        return
    schema = as_dict(as_dict(load(schema_path).get(app)).get("stats"))

    # Your progress: the most recently written account's file, if several people use this Steam
    user_files = sorted(glob.glob(os.path.join(STATS_DIR, f"UserGameStats_*_{app}.bin")), key=os.path.getmtime)
    progress = as_dict(load(user_files[-1]).get("cache")) if user_files else {}

    achievements = []
    for stat_id, stat in schema.items():
        if not isinstance(stat, dict) or not is_achievement_stat(stat):
            continue
        stat_progress = as_dict(progress.get(stat_id))
        bits_unlocked = stat_progress.get("data", 0) & 0xFFFFFFFF
        times = as_dict(stat_progress.get("AchievementTimes"))
        for bit, entry in as_dict(stat.get("bits")).items():
            if not isinstance(entry, dict):
                continue
            display = as_dict(entry.get("display"))
            unlocked = bool((bits_unlocked >> int(bit)) & 1)
            achievements.append({
                "id": entry.get("name", f"{stat_id}_{bit}"),
                "name": localised(display.get("name"), language),
                "description": localised(display.get("desc"), language),
                "hidden": str(display.get("hidden", "0")) == "1",
                "icon": ICON_URL.format(app=app, file=display["icon"]) if display.get("icon") else "",
                "iconGray": ICON_URL.format(app=app, file=display["icon_gray"]) if display.get("icon_gray") else "",
                "unlocked": unlocked,
                "time": int(times.get(bit, 0)) if unlocked else 0,
            })

    finish(app, cache_dir, achievements, "local", None)


def finish(app, cache_dir, achievements, source, error):
    """Adds each one's share of players, orders them, prints the JSON."""
    if achievements:  # Only games that have any need the network
        percents = rarity(app, cache_dir)
        lowered = {k.lower(): v for k, v in percents.items()}  # The profile page's names can differ in case
        for a in achievements:
            a["percent"] = round(percents.get(a["id"], lowered.get(a["id"].lower(), -1)), 1)
    # Unlocked newest first, then locked most common first
    achievements.sort(key=lambda a: (not a["unlocked"], -a["time"] if a["unlocked"] else -a["percent"]))
    missing = cache_icons(app, cache_dir, achievements)
    print(json.dumps({
        "total": len(achievements),
        "unlocked": sum(a["unlocked"] for a in achievements),
        "source": source,
        "error": error,
        "achievements": achievements,
    }, ensure_ascii=False), flush=True)
    fetch_icons(missing)


if __name__ == "__main__":
    main()
