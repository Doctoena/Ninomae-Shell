#!/usr/bin/env python3
"""Parse Steam's packageinfo.vdf binary to extract appids the user has library access to.

Usage: steam_library_appids.py <packageinfo_path> <output_path> [appinfo_path] [removed_list_path]
Writes one appid per line for games from owned packages (billingtype 0,1,3,5,6,10), plus free-to-play
games added with "Add to Library" (billingtype 12) when appinfo shows a free game that isn't a test
server, trial, benchmark or demo. Expired licenses are skipped, and so are the package IDs in the
removed list: Steam never drops a removed license from packageinfo.vdf, so it can't be detected.
Package 0 is skipped too: it's Steam's own, on every account, so its free apps (Dota 2, Spacewar…)
aren't yours just because it lists them.
Platform-only builds Steam hides here (VisibleOnlyOnAvailablePlatforms without windows/linux in
oslist, e.g. the macOS copy of GTA San Andreas) are dropped, or they'd show up as duplicates; their ids
go to steam_hidden_appids.txt next to the output, so the Steam Web API's owned list can skip them too.
Family-shared games come along on their own: their licenses are in packageinfo.vdf like yours.
"""
import os
import re
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # Also when run with -I
from steam_appinfo import apps

_UINT32 = struct.Struct("<I")

# Steam's EBillingType values counted as library access:
#   0  = NoCost (complimentary grants)          5  = HardwarePromo
#   1  = BillOnceOnly (store purchase)          6  = Gift
#   3  = ProofOfPrepurchaseOnly (CD key)        10 = BillOnceOrCDKey
# Only when the app itself is a free game (appinfo isfreeapp):
#   12 = FreeOnDemand: "Add to Library" on a free game, but also free weekends of paid games, which
#        the Steam Web API's owned-games list covers properly when they're really owned
_LIBRARY_BILLING_TYPES = frozenset((0, 1, 3, 5, 6, 10))
_FREE_ON_DEMAND = 12
# Free entries also have to be a game, and not a side build of one: these come along with free licenses
# (public test servers, trial editions, benchmarks, demos) but don't belong in a game launcher
_JUNK_NAME = re.compile(r"\b(public test|test server|test|playtest|trial|benchmark|demo|dedicated server|sdk)\b", re.I)


def read_removed(path):
    """Package IDs from the removed-licenses list (one per line, # comments)."""
    try:
        with open(path) as f:
            return {int(l.split("#")[0]) for l in f if l.split("#")[0].strip().isdigit()}
    except OSError:
        return set()


def parse_packageinfo(packageinfo_path, output_path, appinfo_path=None, removed_path=None):
    removed = read_removed(removed_path) if removed_path else set()
    with open(packageinfo_path, "rb") as f:
        data = f.read()

    dlen = len(data)
    find_nul = data.index  # bind method once
    unpack_u32 = _UINT32.unpack_from

    # Before each package's KeyValues: its id, SHA-1(20) and change number(4), and since v28 an
    # 8-byte PICS token. Skipping too little made every package after the first parse as garbage
    magic = unpack_u32(data, 0)[0]
    package_header = {0x06565527: 24, 0x06565528: 32}.get(magic)
    if package_header is None:
        sys.exit(f"Unsupported packageinfo.vdf version: 0x{magic:08X}")

    now = int(time.time())
    pos = 8  # skip magic(4) + universe(4)
    appids = set()
    appids_update = appids.update  # hot-path binding
    free_candidates = set()

    _KEY_APPIDS = b"appids"
    _KEY_BILLING = b"billingtype"
    _KEY_EXPIRY = b"expirytime"
    _NUL = b"\x00"

    while pos < dlen - 4:
        pkgid = unpack_u32(data, pos)[0]
        pos += 4
        if pkgid == 0xFFFFFFFF:
            break
        pos += package_header

        depth = 0
        pkg_appids = []
        billing_type = -1
        expiry_time = 0
        in_appids = False

        while pos < dlen:
            t = data[pos]
            pos += 1

            if t == 0x08:  # END
                if depth == 0:
                    break
                depth -= 1
                in_appids = False
                continue

            nul = find_nul(_NUL, pos)
            if t == 0x00:  # SUBSECTION
                if not in_appids and data[pos:nul] == _KEY_APPIDS:
                    in_appids = True
                pos = nul + 1
                depth += 1
            elif t == 0x01:  # STRING
                pos = find_nul(_NUL, nul + 1) + 1
            elif t == 0x02:  # INT32
                key = data[pos:nul]
                pos = nul + 1
                val = unpack_u32(data, pos)[0]
                pos += 4
                if in_appids:
                    pkg_appids.append(val)
                elif key == _KEY_BILLING:
                    billing_type = val
                elif key == _KEY_EXPIRY:
                    expiry_time = val
            elif t == 0x07 or t == 0x0A:  # INT64
                pos = nul + 9
            else:
                pos = nul + 1
                if t == 0x03 or t == 0x04 or t == 0x06:
                    pos += 4

        if pkgid == 0 or pkgid in removed:
            continue
        if expiry_time == 0 or expiry_time >= now:
            if billing_type in _LIBRARY_BILLING_TYPES:
                appids_update(pkg_appids)
            elif billing_type == _FREE_ON_DEMAND:
                free_candidates.update(pkg_appids)

    # One appinfo pass for both checks: free candidates that are real games, and owned builds Steam hides here
    free_candidates -= appids
    hidden = set()
    if appinfo_path and os.path.exists(appinfo_path):
        for appid, info in apps(appids | free_candidates, appinfo_path).items():
            common = info.get("common") or {}
            oslist = str(common.get("oslist", ""))
            if (str(common.get("VisibleOnlyOnAvailablePlatforms", 0)) == "1"
                    and oslist and "windows" not in oslist and "linux" not in oslist):
                hidden.add(appid)
            elif (appid in free_candidates
                    and str((info.get("extended") or {}).get("isfreeapp", 0)) == "1"
                    and str(common.get("type", "")).lower() == "game"
                    and not _JUNK_NAME.search(common.get("name", ""))):
                appids.add(appid)
        appids -= hidden

    with open(os.path.join(os.path.dirname(output_path), "steam_hidden_appids.txt"), "w") as out:
        out.write("".join(f"{a}\n" for a in sorted(hidden)))
    with open(output_path, "w") as out:
        out.write("\n".join(map(str, sorted(appids))) + "\n" if appids else "")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4, 5):
        sys.exit(f"Usage: {sys.argv[0]} <packageinfo_path> <output_path> [appinfo_path] [removed_list_path]")
    parse_packageinfo(*sys.argv[1:])
