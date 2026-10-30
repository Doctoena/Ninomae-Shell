#!/usr/bin/env bash

# Game detection script for quickshell game launcher
# Detects games from Steam and Lutris

set -euo pipefail

CACHE_DIR="${1:-$HOME/.cache/game-launcher}"
BOX_ART_DIR="${2:-$CACHE_DIR/box-art}"
# Steam Web API key from the environment (arguments show in ps); curl reads it from there too
export STEAM_API_KEY="${STEAM_API_KEY:-}"
STEAM_DIR="$HOME/.local/share/Steam"
LUTRIS_DIR="$HOME/.config/lutris"
LUTRIS_DATA_DIR="$HOME/.local/share/lutris"

mkdir -p "$CACHE_DIR"
mkdir -p "$BOX_ART_DIR"

# ─── Pre-parse Steam library folder paths (reused throughout) ───────────
declare -a STEAM_LIBRARY_PATHS=("$STEAM_DIR")
if [[ -f "$STEAM_DIR/steamapps/libraryfolders.vdf" ]]; then
    while IFS= read -r _lib_path; do
        [[ -n "$_lib_path" ]] && [[ "$_lib_path" != "$STEAM_DIR" ]] && STEAM_LIBRARY_PATHS+=("$_lib_path")
    done < <(awk -F'"' '/\"path\"/{print $4}' "$STEAM_DIR/steamapps/libraryfolders.vdf" 2>/dev/null)
fi

# ─── Delta detection: skip full re-scan if no manifests/DB changed ──────
FINGERPRINT_FILE="$CACHE_DIR/detect_fingerprint"
CACHED_OUTPUT="$CACHE_DIR/detect_output.json"

_compute_fingerprint() {
    # Scripts + removed-licenses list (invalidate when they change), Steam app/package info + localconfig,
    # Lutris DB and YAMLs: path + mtime, all in a single stat call. Steam manifests by their contents
    # instead, less the download progress: Steam rewrites a downloading game's manifest every few
    # seconds with new Bytes* counts, and by mtime each of those set off a full rescan of the library.
    # Progress is read from the manifests directly (GameDetailsPanel, launch_watch.py), not from here
    local here; here="$(dirname "${BASH_SOURCE[0]}")"
    local -a files=("${BASH_SOURCE[0]}" "$here"/*.py "$CACHE_DIR/custom_games.json"
                    "${XDG_STATE_HOME:-$HOME/.local/state}/ninomae-shell/removed-free-licenses.txt")
    local -a manifests=()
    for lib_root in "${STEAM_LIBRARY_PATHS[@]}"; do
        manifests+=("$lib_root"/steamapps/appmanifest_*.acf)
    done
    files+=("$STEAM_DIR/appcache/appinfo.vdf" "$STEAM_DIR/appcache/packageinfo.vdf"
            "$STEAM_DIR"/userdata/*/config/localconfig.vdf
            "$LUTRIS_DATA_DIR/pga.db" "$LUTRIS_DATA_DIR/games"/*.yml "$LUTRIS_DIR/games"/*.yml)
    {
        stat -c '%n %Y' -- "${files[@]}" 2>/dev/null || true
        local -a present=()
        for m in "${manifests[@]}"; do [[ -f "$m" ]] && present+=("$m"); done
        ((${#present[@]})) && awk 'FNR == 1 { print FILENAME } !/"(Bytes(ToDownload|Downloaded|ToStage|Staged)|StagingSize)"/' \
            "${present[@]}" 2>/dev/null
        # Steam API key presence (invalidate cache if key added/removed)
        echo "steam_api_key=${STEAM_API_KEY:+set}"
    } | md5sum | cut -d' ' -f1
}

_current_fp=$(_compute_fingerprint)

# Validate art paths on disk + detect auto-generated box art (PNG disguised as .jpg).
# One Python pass over the whole list (reads stdin JSON, writes JSON).
read -r -d '' _VALIDATE_ART_PY <<'PY' || true
import json, os, sys
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
games = json.load(sys.stdin)
for g in games:
    for key in ("boxArt", "heroArt", "icon"):
        path = g.get(key) or ""
        g[key] = path if path and os.path.isfile(path) else ""
    box = g["boxArt"]
    partial = False
    if box and "/config/grid/" not in box:
        try:
            with open(box, "rb") as f:
                partial = f.read(8) == PNG_SIGNATURE
        except OSError:
            pass
    g["partialBoxArt"] = partial
json.dump(games, sys.stdout, indent=2, ensure_ascii=False)
print()
PY
_validate_art_paths() {
    python3 -c "$_VALIDATE_ART_PY"
}

if [[ -f "$FINGERPRINT_FILE" ]] && [[ -f "$CACHED_OUTPUT" ]]; then
    _cached_fp=$(cat "$FINGERPRINT_FILE")
    if [[ "$_current_fp" == "$_cached_fp" ]]; then
        _validate_art_paths < "$CACHED_OUTPUT"
        exit 0
    fi
fi

# Initialize games array
declare -a GAMES=()
declare -A PROTONDB_TIER=()
PROTONDB_CACHE_DIR="$CACHE_DIR/protondb"

# Helper: Add game to array as tab-separated record (no per-game jq)
declare -A SEEN_GAME_IDS=()
add_game() {
    local id="$1"
    local name="$2"
    local source="$3"
    local launch_command="$4"
    local box_art="${5:-}"
    local icon="${6:-}"
    local game_dir="${7:-}"
    local playtime="${8:-0}"
    local last_played="${9:-0}"
    local hero_art="${10:-}"
    local build_id="${11:-0}"
    local state_flags="${12:-4}"
    local protondb_tier="${13:-}"
    local runner="${14:-}"      # Lutris: linux, wine, dosbox…
    local flatpak_id="${15:-}"  # Games started with `flatpak run <id>` (their data lives in ~/.var/app/<id>)
    local last_updated="${16:-0}" # Steam: when the installed copy was last updated (s), for "Updated since you last played"

    # Skip if name is empty or contains "Soundtrack"
    local _lname="${name,,}"  # lowercase for matching
    if [[ -z "$name" ]] || [[ "$_lname" =~ soundtrack|playtest|[^a-z]demo([^a-z]|$)|[^a-z]beta([^a-z]|$)|test.server|dedicated.server|[^a-z]sdk([^a-z]|$)|\(obsolete\) ]]; then
        return
    fi

    # Deduplicate by id
    [[ -n "${SEEN_GAME_IDS[$id]:-}" ]] && return
    SEEN_GAME_IDS[$id]=1

    # Validate art paths exist on disk
    [[ -n "$box_art" ]] && [[ ! -f "$box_art" ]] && box_art=""
    [[ -n "$icon" ]] && [[ ! -f "$icon" ]] && icon=""
    [[ -n "$hero_art" ]] && [[ ! -f "$hero_art" ]] && hero_art=""

    # Store as tab-separated fields: id, name, source, launch_command, boxArt, icon, heroArt, gameDir, playtime, lastPlayed, buildId, stateFlags, protondbTier, runner, flatpakId, lastUpdated
    # Real tabs, printed with %s below: the old literal "\t" + printf %b also expanded every other backslash
    # in the fields (a Windows path's "\\" in the launch command's JSON broke fromjson and emptied the list)
    local t=$'\t'
    GAMES+=("${id}${t}${name}${t}${source}${t}${launch_command}${t}${box_art}${t}${icon}${t}${hero_art}${t}${game_dir}${t}${playtime}${t}${last_played}${t}${build_id}${t}${state_flags}${t}${protondb_tier}${t}${runner}${t}${flatpak_id}${t}${last_updated}")
}

# ─── Pre-scan all Steam art into lookup tables (eliminates per-game glob forks) ─
declare -A ART_BOX=() ART_HERO=() ART_ICON=()
# Sets _NEWEST to the most recently changed of the given files that exist (no subshell: it runs per game)
_newest() {
    local f; _NEWEST=""
    for f; do [[ -f $f ]] && [[ -z $_NEWEST || $f -nt $_NEWEST ]] && _NEWEST=$f; done
    return 0
}
_prescan_steam_art() {
    # librarycache/{appid}/: older Steam keeps the art right there, newer Steam in a folder per version
    # ({appid}/{hash}/library_hero.jpg). When an update changes a game's art (Warframe does each update)
    # the old folder can stay behind, so the newest file wins; the first match in hash order could be
    # the old picture (game 2174560 had two heroes and showed the earlier one). A new version is also a
    # new path, so the grid's image cache picks it up straight away.
    local _lc="$STEAM_DIR/appcache/librarycache"
    if [[ -d "$_lc" ]]; then
        for _dir in "$_lc"/*/; do
            [[ -d "$_dir" ]] || continue
            local _aid="${_dir%/}"
            _aid="${_aid##*/}"
            [[ "$_aid" =~ ^[0-9]+$ ]] || continue
            _newest "$_dir"library_600x900.jpg "$_dir"*/library_600x900.jpg
            [[ -z $_NEWEST ]] && _newest "$_dir"*/library_capsule.jpg # Portrait cover first, then the capsule
            [[ -n $_NEWEST ]] && ART_BOX[$_aid]=$_NEWEST
            _newest "$_dir"library_hero.jpg "$_dir"*/library_hero.jpg
            [[ -n $_NEWEST ]] && ART_HERO[$_aid]=$_NEWEST
            _newest "$_dir"logo.png "$_dir"*/logo.png
            [[ -n $_NEWEST ]] && ART_ICON[$_aid]=$_NEWEST
        done
    fi
    # Custom grid art (highest priority — overrides librarycache)
    for _grid in "$STEAM_DIR"/userdata/*/config/grid/*p.png "$STEAM_DIR"/userdata/*/config/grid/*p.jpg; do
        [[ -f "$_grid" ]] || continue
        local _base="${_grid##*/}"
        local _aid="${_base%p.*}"
        ART_BOX[$_aid]="$_grid"
    done
    # CDN-cached art from box-art dir
    for _cdn in "$BOX_ART_DIR"/steam_*; do
        [[ -f "$_cdn" ]] || continue
        local _base="${_cdn##*/}"
        case "$_base" in
            steam_*_box.jpg)  local _aid="${_base#steam_}"; _aid="${_aid%_box.jpg}";  [[ -z "${ART_BOX[$_aid]:-}" ]] && ART_BOX[$_aid]="$_cdn" ;;
            steam_*_hero.jpg) local _aid="${_base#steam_}"; _aid="${_aid%_hero.jpg}"; [[ -z "${ART_HERO[$_aid]:-}" ]] && ART_HERO[$_aid]="$_cdn" ;;
            steam_*_logo.png) local _aid="${_base#steam_}"; _aid="${_aid%_logo.png}"; [[ -z "${ART_ICON[$_aid]:-}" ]] && ART_ICON[$_aid]="$_cdn" ;;
        esac
    done
    return 0  # last [[ ]] && ... may be false; don't let set -e kill the script
}
_prescan_steam_art

# Pre-parse ALL Steam playtime + owned appids once using awk
declare -A STEAM_PLAYTIME=()
declare -A STEAM_LASTPLAYED=()
declare -A STEAM_OWNED_APPIDS=()
_preparse_steam_data() {
    local awk_output
    awk_output=$(cat "$STEAM_DIR"/userdata/*/config/localconfig.vdf 2>/dev/null | awk '
        /^[[:space:]]*"[0-9]+"[[:space:]]*$/ {
            gsub(/[" \t]/, "")
            appid = $0
            owned[appid] = 1
            next
        }
        appid && /"Playtime"/ {
            match($0, /"Playtime"[[:space:]]*"([0-9]+)"/, m)
            if (m[1]+0 > pt[appid]+0) pt[appid] = m[1]
        }
        appid && /"LastPlayed"/ {
            match($0, /"LastPlayed"[[:space:]]*"([0-9]+)"/, m)
            if (m[1]+0 > lp[appid]+0) lp[appid] = m[1]
        }
        appid && /^[[:space:]]*\}/ { appid = "" }
        END {
            for (id in owned) {
                printf "%s\t%s\t%s\n", id, (id in pt ? pt[id] : 0), (id in lp ? lp[id] : 0)
            }
        }
    ')
    while IFS=$'\t' read -r appid pt lp; do
        [[ -z "$appid" ]] && continue
        STEAM_OWNED_APPIDS[$appid]=1
        [[ "$pt" != "0" ]] && STEAM_PLAYTIME[$appid]="$pt"
        [[ "$lp" != "0" ]] && STEAM_LASTPLAYED[$appid]="$lp"
    done <<< "$awk_output" || true
}
if [[ -d "$STEAM_DIR/userdata" ]]; then
    _preparse_steam_data
fi

# Pre-collect installed Steam appids (reused by prefetch + uninstalled detection)
declare -A INSTALLED_APPIDS=()
for _lib in "${STEAM_LIBRARY_PATHS[@]}"; do
    for _m in "$_lib"/steamapps/appmanifest_*.acf; do
        [[ -f "$_m" ]] || continue
        _a="${_m##*/appmanifest_}"
        INSTALLED_APPIDS["${_a%.acf}"]=1
    done
done

# Pre-parse packageinfo.vdf appids so ProtonDB prefetch covers the full library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBRARY_APPIDS_CACHE="$CACHE_DIR/steam_library_appids.txt"
_packageinfo="$STEAM_DIR/appcache/packageinfo.vdf"
if [[ -f "$_packageinfo" ]]; then
    python3 "$SCRIPT_DIR/steam_library_appids.py" "$_packageinfo" "$LIBRARY_APPIDS_CACHE" "$STEAM_DIR/appcache/appinfo.vdf" \
        "${XDG_STATE_HOME:-$HOME/.local/state}/ninomae-shell/removed-free-licenses.txt" 2>/dev/null || true
fi
if [[ -f "$LIBRARY_APPIDS_CACHE" ]] && [[ -s "$LIBRARY_APPIDS_CACHE" ]]; then
    while IFS= read -r _pid; do
        [[ -n "$_pid" ]] && STEAM_OWNED_APPIDS[$_pid]=1
    done < "$LIBRARY_APPIDS_CACHE"
fi
# Builds Steam hides on this platform (macOS-only copies): skipped whichever list brings them in
declare -A HIDDEN_APPIDS=()
if [[ -f "$CACHE_DIR/steam_hidden_appids.txt" ]]; then
    while IFS= read -r _pid; do
        [[ -n "$_pid" ]] && HIDDEN_APPIDS[$_pid]=1
    done < "$CACHE_DIR/steam_hidden_appids.txt"
fi

# Pre-parse Steam app names (reused by ProtonDB filter + uninstalled games)
declare -A APP_NAMES=()
APPNAMES_CACHE="$CACHE_DIR/steam_appnames.tsv"
if [[ -f "$STEAM_DIR/appcache/appinfo.vdf" ]]; then
    python3 "$SCRIPT_DIR/steam_appnames.py" "$STEAM_DIR/appcache/appinfo.vdf" "$APPNAMES_CACHE" 2>/dev/null || true
    if [[ -f "$APPNAMES_CACHE" ]]; then
        while IFS=$'\t' read -r _aid _aname; do
            [[ -n "$_aid" ]] && APP_NAMES[$_aid]="$_aname"
        done < "$APPNAMES_CACHE"
    fi
fi

# Pre-fetch ProtonDB compatibility ratings for all Steam games (cached for 7 days)
_prefetch_protondb() {
    [[ -d "$STEAM_DIR" ]] || return
    mkdir -p "$PROTONDB_CACHE_DIR"

    local needs_fetch=()
    local now
    now=$(date +%s)

    # Merge installed + owned appids (only those with known names — skip DLCs/tools/servers)
    declare -A _all_appids=()
    local appid
    for appid in "${!INSTALLED_APPIDS[@]}" "${!STEAM_OWNED_APPIDS[@]}"; do
        [[ -n "${APP_NAMES[$appid]:-}" ]] && _all_appids[$appid]=1
    done

    # Bulk-read cached ProtonDB tiers using single grep pass (avoids per-file reads)
    local _cutoff=$((now - 604800))
    declare -A _protondb_cached=()

    # Two-pass approach: stat to find fresh files, then grep all at once for tiers
    local -a _fresh_files=()
    local _fpath _mtime
    while IFS=' ' read -r _fpath _mtime; do
        [[ -z "$_fpath" ]] && continue
        local appid="${_fpath##*/}"
        appid="${appid%.json}"
        if [[ $_mtime -gt $_cutoff ]]; then
            _protondb_cached[$appid]=1
            _fresh_files+=("$_fpath")
        fi
    done < <(stat -c '%n %Y' "$PROTONDB_CACHE_DIR"/*.json 2>/dev/null || true)

    # Single grep extracts all tiers at once: "filepath:tier_value"
    if [[ ${#_fresh_files[@]} -gt 0 ]]; then
        while IFS=: read -r _gpath _gtier; do
            [[ -z "$_gtier" || "$_gtier" == "null" ]] && continue
            local appid="${_gpath##*/}"
            appid="${appid%.json}"
            PROTONDB_TIER[$appid]="$_gtier"
        done < <(grep -oHP '"tier":\s*"\K[^"]+' "${_fresh_files[@]}" 2>/dev/null || true)
    fi

    # Build fetch list: appids without fresh cache
    for appid in "${!_all_appids[@]}"; do
        [[ -n "${_protondb_cached[$appid]:-}" ]] && continue
        needs_fetch+=("$appid")
    done

    # Batch-fetch missing ratings in parallel (max 50 concurrent, HTTP/2)
    if [[ ${#needs_fetch[@]} -gt 0 ]]; then
        printf '%s\n' "${needs_fetch[@]}" | xargs -P 50 -I{} \
            curl -sL --http2 --max-time 3 --retry 1 --retry-delay 1 \
                "https://www.protondb.com/api/v1/reports/summaries/{}.json" \
                -o "$PROTONDB_CACHE_DIR/{}.json" 2>/dev/null || true

        # Read freshly fetched results into map
        for appid in "${needs_fetch[@]}"; do
            local cache_file="$PROTONDB_CACHE_DIR/${appid}.json"
            if [[ -f "$cache_file" ]]; then
                local _content
                _content=$(<"$cache_file") 2>/dev/null || { rm -f "$cache_file"; continue; }
                if [[ "$_content" =~ \"tier\":[[:space:]]*\"([^\"]+)\" ]] && [[ "${BASH_REMATCH[1]}" != "null" ]]; then
                    PROTONDB_TIER[$appid]="${BASH_REMATCH[1]}"
                else
                    # No rating (usually no reports yet): cache that too, re-checked after 7 days
                    echo '{"tier": null}' > "$cache_file"
                fi
            fi
        done
    fi
}
_prefetch_protondb

# Detect Steam games
detect_steam_games() {
    [[ -d "$STEAM_DIR" ]] || return

    for library in "${STEAM_LIBRARY_PATHS[@]}"; do
        [[ -d "$library/steamapps" ]] || continue

        for manifest in "$library"/steamapps/appmanifest_*.acf; do
            [[ -f "$manifest" ]] || continue

            # Extract appid from filename (no subshell)
            local _base="${manifest##*/}"
            local appid="${_base#appmanifest_}"
            appid="${appid%.acf}"

            # Single awk pass for all manifest fields
            local name buildid stateflags installdir lastupdated
            IFS=$'\t' read -r name buildid stateflags installdir lastupdated < <(awk -F'"' '
                /"name"/ && !n { n=$4; next }
                /"buildid"/ && !b { b=$4; next }
                /"StateFlags"/ && !s { s=$4; next }
                /"installdir"/ && !d { d=$4; next }
                /"LastUpdated"/ && !u { u=$4; next }
                END { printf "%s\t%s\t%s\t%s\t%s\n", n, b, s, d, u }
            ' "$manifest")
            name="${name//[™®]/}"
            : "${buildid:=0}" "${stateflags:=4}" "${lastupdated:=0}"

            local box_art="${ART_BOX[$appid]:-}"
            local hero_art="${ART_HERO[$appid]:-}"
            local icon="${ART_ICON[$appid]:-}"
            local game_dir="$library/steamapps/common/$installdir"

            local playtime="${STEAM_PLAYTIME[$appid]:-0}"
            local last_played="${STEAM_LASTPLAYED[$appid]:-0}"
            [[ "$last_played" -gt 0 ]] && last_played=$((last_played * 1000))

            local launch_cmd='["steam", "-silent", "steam://rungameid/'$appid'"]'
            add_game "steam_$appid" "$name" "Steam" "$launch_cmd" "$box_art" "$icon" "$game_dir" "$playtime" "$last_played" "$hero_art" "$buildid" "$stateflags" "${PROTONDB_TIER[$appid]:-}" "" "" "$lastupdated"
        done
    done
}

# Detect uninstalled Steam games (owned but not installed)
detect_uninstalled_steam_games() {
    [[ -d "$STEAM_DIR" ]] || return
    [[ ${#APP_NAMES[@]} -gt 0 ]] || return

    # Build the set of appids to iterate: Steam Web API (family share) or localconfig fallback
    declare -A UNINSTALLED_CANDIDATES=()

    # With a Steam Web API key: your games and each Steam Family member's, from Steam's owned-games list.
    # It's current, unlike packageinfo.vdf (below), which keeps every license Steam ever saw, so games
    # removed from the library came back (1,323 here against Steam's 1,031). A member's games count only
    # when packageinfo.vdf has their license too: that's how family sharing reaches this account, and it
    # leaves out games that can't be shared. A member with private game details adds nothing.
    local _api_ok=false
    if [[ -n "$STEAM_API_KEY" ]]; then
        local steam_id="" _lc_cfg
        if [[ -f "$STEAM_DIR/config/loginusers.vdf" ]]; then
            steam_id=$(awk -F'"' '/^[[:space:]]*"[0-9]{17}"/ && !found { print $2; found=1 }' "$STEAM_DIR/config/loginusers.vdf")
        fi
        if [[ -n "$steam_id" ]]; then
            local -a _family_ids=()
            _lc_cfg="$STEAM_DIR/userdata/$((steam_id - 76561197960265728))/config/localconfig.vdf"
            # Account ids → Steam ids in bash (64-bit integers): awk's doubles round them (…283 became …280)
            local _acct
            [[ -f "$_lc_cfg" ]] && while IFS= read -r _acct; do
                [[ "$_acct" =~ ^[0-9]+$ ]] && _family_ids+=("$((76561197960265728 + _acct))")
            done < <(awk -F'"' '/^\t"FamilyGroup"/ { fg = 1 } fg && /^\t}/ { fg = 0 } fg && $2 == "accountid" { print $4 }' "$_lc_cfg")
            declare -A _family_apps=()
            local _sid _api_cache _mtime _own
            declare -A _asked=()
            for _sid in "$steam_id" "${_family_ids[@]}"; do # The family list includes you: asked once
                [[ -n "$_sid" && -z "${_asked[$_sid]:-}" ]] || continue
                _asked[$_sid]=1
                _own=false; [[ "$_sid" == "$steam_id" ]] && _own=true
                _api_cache="$CACHE_DIR/steam_api_library_$_sid.json"
                _mtime=$(stat -c %Y "$_api_cache" 2>/dev/null || echo 0)
                if (( $(date +%s) - _mtime >= 86400 )); then # Re-asked once a day
                    curl -sL --max-time 10 --retry 1 --retry-delay 2 --variable %STEAM_API_KEY --expand-url \
                        "https://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key={{STEAM_API_KEY}}&steamid=${_sid}&include_played_free_games=1&include_appinfo=1&format=json" \
                        -o "$_api_cache.tmp" 2>/dev/null || true
                    if [[ -f "$_api_cache.tmp" ]] && jq -e '.response' "$_api_cache.tmp" >/dev/null 2>&1; then
                        mv "$_api_cache.tmp" "$_api_cache"
                    else
                        rm -f "$_api_cache.tmp"
                    fi
                fi
                [[ -f "$_api_cache" ]] || continue
                if $_own; then
                    OWN_API_CACHE="$_api_cache" # Its two-week playtime is merged into the output below
                    jq -e '.response.games' "$_api_cache" >/dev/null 2>&1 && _api_ok=true
                    while IFS=$'\t' read -r _api_appid _api_name _api_pt _api_lp; do
                        [[ -z "$_api_appid" ]] && continue
                        UNINSTALLED_CANDIDATES[$_api_appid]=1
                        # API names, playtime and last played fill in what appinfo/localconfig don't have
                        [[ -z "${APP_NAMES[$_api_appid]:-}" ]] && [[ -n "$_api_name" ]] && APP_NAMES[$_api_appid]="$_api_name"
                        [[ -z "${STEAM_PLAYTIME[$_api_appid]:-}" ]] && [[ "$_api_pt" != "0" ]] && STEAM_PLAYTIME[$_api_appid]="$_api_pt"
                        [[ -z "${STEAM_LASTPLAYED[$_api_appid]:-}" ]] && [[ "$_api_lp" != "0" ]] && STEAM_LASTPLAYED[$_api_appid]="$_api_lp"
                    done < <(jq -r '.response.games[]? | [.appid, .name, .playtime_forever, .rtime_last_played] | @tsv' "$_api_cache" 2>/dev/null)
                else
                    while IFS= read -r _api_appid; do
                        [[ -n "$_api_appid" ]] && _family_apps[$_api_appid]=1
                    done < <(jq -r '.response.games[]?.appid' "$_api_cache" 2>/dev/null)
                fi
            done
            rm -f "$CACHE_DIR/steam_api_library.json" # The old single-account cache
            if $_api_ok && [[ -s "$LIBRARY_APPIDS_CACHE" ]]; then
                while IFS= read -r appid; do
                    [[ -n "$appid" && -n "${_family_apps[$appid]:-}" ]] && UNINSTALLED_CANDIDATES[$appid]=1
                done < "$LIBRARY_APPIDS_CACHE"
            fi
        fi
    fi

    # Without a key (or when Steam's API didn't answer): every license in packageinfo.vdf (already parsed)
    if ! $_api_ok; then
        if [[ -f "$LIBRARY_APPIDS_CACHE" ]] && [[ -s "$LIBRARY_APPIDS_CACHE" ]]; then
            while IFS= read -r appid; do
                [[ -n "$appid" ]] && UNINSTALLED_CANDIDATES[$appid]=1
            done < "$LIBRARY_APPIDS_CACHE"
            # (Played apps aren't added from localconfig.vdf: Steam keeps their playtime after a game
            # is removed from the library, so they'd bring removed free games back)
        elif [[ ${#UNINSTALLED_CANDIDATES[@]} -eq 0 ]]; then
            # Final fallback: localconfig owned appids
            for appid in "${!STEAM_OWNED_APPIDS[@]}"; do
                UNINSTALLED_CANDIDATES[$appid]=1
            done
        fi
    fi

    # Collect uninstalled games and batch-fetch missing CDN art in parallel
    local -a _cdn_fetch_box=() _cdn_fetch_hero=() _cdn_fetch_logo=()
    local -a _uninstalled_appids=()

    for appid in "${!UNINSTALLED_CANDIDATES[@]}"; do
        [[ -n "${INSTALLED_APPIDS[$appid]:-}" ]] && continue
        [[ -z "${APP_NAMES[$appid]:-}" ]] && continue
        [[ -n "${HIDDEN_APPIDS[$appid]:-}" ]] && continue

        _uninstalled_appids+=("$appid")

        # Queue CDN fetches for games missing local art (skipping known misses, see below)
        local _b="$BOX_ART_DIR/steam_${appid}"
        if [[ -z "${ART_BOX[$appid]:-}" ]] && [[ ! -f "${_b}_box.jpg" ]] && [[ ! -f "${_b}_box.jpg.missing" ]]; then
            _cdn_fetch_box+=("$appid")
        fi
        if [[ -z "${ART_HERO[$appid]:-}" ]] && [[ ! -f "${_b}_hero.jpg" ]] && [[ ! -f "${_b}_hero.jpg.missing" ]]; then
            _cdn_fetch_hero+=("$appid")
        fi
        if [[ -z "${ART_ICON[$appid]:-}" ]] && [[ ! -f "${_b}_logo.png" ]] && [[ ! -f "${_b}_logo.png.missing" ]]; then
            _cdn_fetch_logo+=("$appid")
        fi
    done

    # Helper: batch-download from Steam CDN in parallel.
    # Art the CDN doesn't have leaves a .missing marker so it isn't retried every scan;
    # markers expire after 7 days.
    find "$BOX_ART_DIR" -maxdepth 1 -name '*.missing' -mtime +7 -delete 2>/dev/null || true
    _cdn_batch_fetch() {
        local -n _appids=$1
        local suffix="$2" cdn_path="$3"
        [[ ${#_appids[@]} -eq 0 ]] && return
        printf '%s\n' "${_appids[@]}" | xargs -P 30 -I{} bash -c '
            f="'"$BOX_ART_DIR"'/steam_{}_'"$suffix"'"
            curl -sL --max-time 3 --retry 1 --retry-delay 1 "https://cdn.akamai.steamstatic.com/steam/apps/{}/'"$cdn_path"'" -o "$f" 2>/dev/null || true
            if [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null || echo 0)" -lt 1000 ]; then rm -f "$f"; touch "$f.missing"; fi
        '
    }
    _cdn_batch_fetch _cdn_fetch_box  "box.jpg"  "library_600x900.jpg"
    _cdn_batch_fetch _cdn_fetch_hero "hero.jpg" "library_hero.jpg"
    _cdn_batch_fetch _cdn_fetch_logo "logo.png" "logo.png"

    # Second pass: emit games with resolved art paths
    for appid in "${_uninstalled_appids[@]}"; do
        local name="${APP_NAMES[$appid]}"
        local box_art="${ART_BOX[$appid]:-}"
        [[ -z "$box_art" ]] && [[ -f "$BOX_ART_DIR/steam_${appid}_box.jpg" ]] && box_art="$BOX_ART_DIR/steam_${appid}_box.jpg"
        local hero_art="${ART_HERO[$appid]:-}"
        [[ -z "$hero_art" ]] && [[ -f "$BOX_ART_DIR/steam_${appid}_hero.jpg" ]] && hero_art="$BOX_ART_DIR/steam_${appid}_hero.jpg"
        local icon="${ART_ICON[$appid]:-}"
        [[ -z "$icon" ]] && [[ -f "$BOX_ART_DIR/steam_${appid}_logo.png" ]] && icon="$BOX_ART_DIR/steam_${appid}_logo.png"

        local launch_cmd='["steam", "-silent", "steam://rungameid/'$appid'"]'
        local playtime="${STEAM_PLAYTIME[$appid]:-0}"
        local last_played="${STEAM_LASTPLAYED[$appid]:-0}"
        [[ "$last_played" -gt 0 ]] && last_played=$((last_played * 1000))

        add_game "steam_$appid" "$name" "Steam" "$launch_cmd" "$box_art" "$icon" "" "$playtime" "$last_played" "$hero_art" "0" "0" "${PROTONDB_TIER[$appid]:-}"
    done
}

# ─── Lutris art helper ──────────────────────────────────────────────────
_find_lutris_art() {
    local slug="$1"
    shift
    for subdir in "$@"; do
        for base in "$LUTRIS_DATA_DIR" "$LUTRIS_DIR"; do
            for ext in jpg png; do
                [[ -f "$base/$subdir/$slug.$ext" ]] && echo "$base/$subdir/$slug.$ext" && return
            done
        done
    done
}

# Detect Lutris games
detect_lutris_games() {
    local lutris_games_dirs=()
    [[ -d "$LUTRIS_DATA_DIR/games" ]] && lutris_games_dirs+=("$LUTRIS_DATA_DIR")
    [[ -d "$LUTRIS_DIR/games" ]] && lutris_games_dirs+=("$LUTRIS_DIR")

    if [[ ${#lutris_games_dirs[@]} -eq 0 ]]; then
        return
    fi

    # Query playtime and lastplayed from Lutris database
    local LUTRIS_DB="$HOME/.local/share/lutris/pga.db"
    local _has_db=false
    [[ -f "$LUTRIS_DB" ]] && command -v sqlite3 &>/dev/null && _has_db=true

    local -A seen_slugs=()
    # sqlite3's command line has no "?" parameters (an extra argument is run as more SQL, which failed
    # silently), so values are quoted into the query
    _sql_quote() { printf "'%s'" "${1//\'/\'\'}"; }

    # Phase 1: Parse all YAML files once and collect data + API fetch list
    declare -A _lut_name=() _lut_slug=() _lut_svc=() _lut_sid=() _lut_flatpak=()
    local _lut_files=() _needs_api=()
    for _base in "${lutris_games_dirs[@]}"; do
        for _file in "$_base/games"/*.yml; do
            [[ -f "$_file" ]] || continue
            _lut_files+=("$_file")
            local _n _gs _s _sv _si _yaml_data
            _yaml_data=$(yq -r '[.name // "", .game_slug // "", .slug // "", .service // "", .service_id // ""] | @tsv' "$_file" 2>/dev/null) || true
            if [[ -n "$_yaml_data" ]]; then
                IFS=$'\t' read -r _n _gs _s _sv _si <<< "$_yaml_data"
            else
                _n=$(grep "^name:" "$_file" 2>/dev/null | head -1 | cut -d: -f2- | xargs) || true
                _gs=$(grep "^game_slug:" "$_file" 2>/dev/null | head -1 | cut -d: -f2- | xargs) || true
                _s=$(grep "^slug:" "$_file" 2>/dev/null | head -1 | cut -d: -f2- | xargs) || true
                _sv=$(grep "^service:" "$_file" 2>/dev/null | head -1 | cut -d: -f2- | xargs) || true
                _si=$(grep "^service_id:" "$_file" 2>/dev/null | head -1 | cut -d: -f2- | xargs) || true
            fi
            [[ -z "$_gs" ]] && _gs="$_s"
            _lut_name["$_file"]="$_n"; _lut_slug["$_file"]="$_gs"
            _lut_svc["$_file"]="$_sv"; _lut_sid["$_file"]="$_si"
            # `game: exe: …flatpak, args: run <app id> …` → the Flatpak's id (first argument after run
            # that isn't an option)
            _lut_flatpak["$_file"]=$(awk '/^game:/ { g = 1; next } /^[^ ]/ { g = 0 }
                g && /^  exe:/ && /flatpak/ { fp = 1 }
                g && /^  args:/ { sub(/^  args:[ ]*/, ""); args = $0 }
                END { if (fp) { n = split(args, a, " "); for (i = 1; i < n; i++) if (a[i] == "run") { for (j = i + 1; j <= n; j++) if (a[j] !~ /^-/) { print a[j]; exit } } } }' "$_file" 2>/dev/null) || true
            if [[ -n "$_gs" ]] && { [[ "$_sv" != "steam" ]] || [[ -z "$_si" ]]; }; then
                [[ -f "$BOX_ART_DIR/lutris_${_gs}_api.json" ]] || _needs_api+=("$_gs")
            fi
        done
    done

    # Phase 2: Batch-fetch Lutris API data in parallel via xargs
    if [[ ${#_needs_api[@]} -gt 0 ]]; then
        printf '%s\n' "${_needs_api[@]}" | sort -u | xargs -P 20 -I{} bash -c '
            curl -sL --max-time 5 --retry 1 --retry-delay 1 "https://lutris.net/api/games/{}" -o "'"$BOX_ART_DIR"'/lutris_{}_api.json" 2>/dev/null || true
            f="'"$BOX_ART_DIR"'/lutris_{}_api.json"
            # Only drop a download that is not real API data. Ends with true: as the last command a
            # failed test made the job exit 1, xargs exit 123 and set -e kill the whole scan
            if [[ -f "$f" ]] && ! jq -e ".slug" "$f" &>/dev/null; then rm -f "$f"; fi
            true
        ' || true
    fi

    # Phase 3: Process each game using pre-parsed data
    for game_file in "${_lut_files[@]}"; do

            local name="${_lut_name[$game_file]}"
            local game_slug="${_lut_slug[$game_file]}"
            local service="${_lut_svc[$game_file]}"
            local service_id="${_lut_sid[$game_file]}"

            # DB fallback for incomplete YAML
            if [[ -z "$name" || -z "$game_slug" ]] && $_has_db; then
                local config_slug db_info
                config_slug=$(basename "$game_file" .yml)
                db_info=$(sqlite3 "$LUTRIS_DB" \
                    "SELECT name, slug FROM games WHERE configpath=$(_sql_quote "$config_slug") AND installed=1 LIMIT 1;" 2>/dev/null || true)
                if [[ -n "$db_info" ]]; then
                    [[ -z "$name" ]] && name="${db_info%%|*}"
                    [[ -z "$game_slug" ]] && game_slug="${db_info#*|}"
                fi
            fi

            [[ -z "$name" || -z "$game_slug" ]] && continue

            # Skip Steam-backed entries without installed manifest
            if [[ "$service" == "steam" && -n "$service_id" ]]; then
                local _found=false
                for _lib in "${STEAM_LIBRARY_PATHS[@]}"; do
                    [[ -f "$_lib/steamapps/appmanifest_${service_id}.acf" ]] && { _found=true; break; }
                done
                $_found || continue
            fi

            [[ -n "${seen_slugs[$game_slug]+x}" ]] && continue
            seen_slugs[$game_slug]=1

            local box_art=$(_find_lutris_art "$game_slug" coverart banners)
            local icon=$(_find_lutris_art "$game_slug" icons)
            local hero_art=""

            local steam_appid=""
            if [[ "$service" == "steam" && -n "$service_id" ]]; then
                steam_appid="$service_id"
            else
                # Read from pre-fetched API cache
                local api_cache="$BOX_ART_DIR/lutris_${game_slug}_api.json"
                if [[ -f "$api_cache" ]]; then
                    steam_appid=$(jq -r '.steamid // empty' "$api_cache" 2>/dev/null || true)
                    [[ "$steam_appid" == "null" || "$steam_appid" == "None" || ! "$steam_appid" =~ ^[0-9]+$ ]] && steam_appid="" # The API says "None"

                    # Grab IGDB coverart URL for box art fallback
                    if [[ -z "$box_art" ]]; then
                        local igdb_url=$(jq -r '.coverart // empty' "$api_cache" 2>/dev/null || true)
                        if [[ -n "$igdb_url" ]] && [[ "$igdb_url" != "null" ]]; then
                            local igdb_1080p="${igdb_url//\/cover_big\///t_1080p/}"
                        igdb_1080p="${igdb_1080p//\/t_cover_big\///t_1080p/}"
                            local coverart_cache="$BOX_ART_DIR/lutris_${game_slug}_cover.jpg"
                            if [[ ! -f "$coverart_cache" ]]; then
                                curl -sL --max-time 3 --retry 1 --retry-delay 1 "$igdb_1080p" -o "$coverart_cache" 2>/dev/null || true
                                [[ -f "$coverart_cache" ]] && [[ $(stat -c%s "$coverart_cache" 2>/dev/null || echo 0) -lt 1000 ]] && rm -f "$coverart_cache"
                            fi
                            [[ -f "$coverart_cache" ]] && box_art="$coverart_cache"
                        fi
                    fi
                fi
            fi

            if [[ -n "$steam_appid" ]]; then
                local hero_cache="$BOX_ART_DIR/lutris_${game_slug}_hero.jpg"
                local logo_cache="$BOX_ART_DIR/lutris_${game_slug}_logo.png"

                # Download hero art from Steam CDN if not cached
                if [[ ! -f "$hero_cache" ]]; then
                    curl -sL --max-time 3 --retry 1 --retry-delay 1 \
                        "https://cdn.akamai.steamstatic.com/steam/apps/${steam_appid}/library_hero.jpg" \
                        -o "$hero_cache" 2>/dev/null || true
                    # Remove if download failed (empty or too small)
                    [[ -f "$hero_cache" ]] && [[ $(stat -c%s "$hero_cache" 2>/dev/null || echo 0) -lt 1000 ]] && rm -f "$hero_cache"
                fi
                [[ -f "$hero_cache" ]] && hero_art="$hero_cache"

                # Download logo from Steam CDN if not cached
                if [[ -z "$icon" ]] && [[ ! -f "$logo_cache" ]]; then
                    curl -sL --max-time 3 --retry 1 --retry-delay 1 \
                        "https://cdn.akamai.steamstatic.com/steam/apps/${steam_appid}/logo.png" \
                        -o "$logo_cache" 2>/dev/null || true
                    [[ -f "$logo_cache" ]] && [[ $(stat -c%s "$logo_cache" 2>/dev/null || echo 0) -lt 1000 ]] && rm -f "$logo_cache"
                fi
                [[ -z "$icon" ]] && [[ -f "$logo_cache" ]] && icon="$logo_cache"

                # Also grab high-res box art from Steam CDN if we don't already have good coverart
                # Override Lutris local banners and coverart (low-res IGDB images that may
                # represent a different edition of the game) with accurate Steam CDN art.
                if [[ -z "$box_art" ]] || [[ "$box_art" == *"/banners/"* ]] || [[ "$box_art" == *"/coverart/"* ]]; then
                    local steam_box_cache="$BOX_ART_DIR/lutris_${game_slug}_box.jpg"
                    if [[ ! -f "$steam_box_cache" ]]; then
                        curl -sL --max-time 3 --retry 1 --retry-delay 1 \
                            "https://cdn.akamai.steamstatic.com/steam/apps/${steam_appid}/library_600x900.jpg" \
                            -o "$steam_box_cache" 2>/dev/null || true
                        [[ -f "$steam_box_cache" ]] && [[ $(stat -c%s "$steam_box_cache" 2>/dev/null || echo 0) -lt 1000 ]] && rm -f "$steam_box_cache"
                    fi
                    [[ -f "$steam_box_cache" ]] && box_art="$steam_box_cache"
                fi
            fi

            [[ -z "$hero_art" ]] && hero_art=$(_find_lutris_art "$game_slug" banners)

            local launch_cmd='["lutris", "lutris:rungame/'$game_slug'"]'

            # Pull playtime (hours→minutes), lastplayed (seconds→ms) and the install folder from Lutris DB
            local lutris_playtime=0
            local lutris_lastplayed=0
            local lutris_dir=""
            local lutris_runner=""
            if $_has_db; then
                local db_row
                db_row=$(sqlite3 "$LUTRIS_DB" \
                    "SELECT COALESCE(playtime,0), COALESCE(lastplayed,0), COALESCE(directory,''), COALESCE(runner,'') FROM games WHERE slug=$(_sql_quote "$game_slug") LIMIT 1;" 2>/dev/null || true)
                if [[ -n "$db_row" ]]; then
                    local db_pt db_lp
                    IFS='|' read -r db_pt db_lp lutris_dir lutris_runner <<< "$db_row"
                    lutris_playtime=$(awk -v h="$db_pt" 'BEGIN { printf "%d", h * 60 }')
                    [[ "$db_lp" -gt 0 ]] 2>/dev/null && lutris_lastplayed=$((db_lp * 1000))
                fi
            fi

            local _pdb_tier=""
            [[ -n "$steam_appid" ]] && _pdb_tier="${PROTONDB_TIER[$steam_appid]:-}"
            add_game "lutris_$game_slug" "$name" "Lutris" "$launch_cmd" "$box_art" "$icon" "$lutris_dir" "$lutris_playtime" "$lutris_lastplayed" "$hero_art" "" "" "$_pdb_tier" "$lutris_runner" "${_lut_flatpak[$game_file]:-}"
    done

    # Second pass: detect installed games in the Lutris DB that weren't found
    # via YAML scanning (e.g. missing or unreadable YAML config files).
    if $_has_db; then
        local db_games
        db_games=$(sqlite3 "$LUTRIS_DB" \
            "SELECT slug, name, COALESCE(service,''), COALESCE(service_id,''), COALESCE(playtime,0), COALESCE(lastplayed,0), COALESCE(directory,''), COALESCE(runner,'') FROM games WHERE installed=1;" 2>/dev/null || true)
        while IFS='|' read -r db_slug db_name db_svc db_svc_id db_pt db_lp db_dir db_runner; do
            [[ -z "$db_slug" ]] && continue
            [[ -z "$db_name" ]] && continue

            [[ -n "${seen_slugs[$db_slug]+x}" ]] && continue

            if [[ "$db_svc" == "steam" && -n "$db_svc_id" ]]; then
                local _found=false
                for _lib in "${STEAM_LIBRARY_PATHS[@]}"; do
                    [[ -f "$_lib/steamapps/appmanifest_${db_svc_id}.acf" ]] && { _found=true; break; }
                done
                $_found || continue
            fi

            local box_art=$(_find_lutris_art "$db_slug" coverart banners)
            local icon=$(_find_lutris_art "$db_slug" icons)
            local hero_art=$(_find_lutris_art "$db_slug" banners)
            local launch_cmd='["lutris", "lutris:rungame/'$db_slug'"]'

            local playtime_min=0 lastplayed_ms=0
            playtime_min=$(awk -v h="$db_pt" 'BEGIN { printf "%d", h * 60 }')
            [[ "$db_lp" -gt 0 ]] 2>/dev/null && lastplayed_ms=$((db_lp * 1000))

            local _pdb_tier=""
            [[ "$db_svc" == "steam" ]] && [[ -n "$db_svc_id" ]] && _pdb_tier="${PROTONDB_TIER[$db_svc_id]:-}"
            add_game "lutris_$db_slug" "$db_name" "Lutris" "$launch_cmd" "$box_art" "$icon" "$db_dir" "$playtime_min" "$lastplayed_ms" "$hero_art" "" "" "$_pdb_tier" "$db_runner"
        done <<< "$db_games"
    fi
}



# Games added by hand in the launcher (any app: a Flatpak, an AppImage, a command), from
# custom_games.json, which GameLauncherService writes: [{ id, name, command: [argv], icon, flatpakId, gameDir }]
# An icon theme name (a desktop entry's Icon=) as a file: the biggest PNG of it in the usual icon
# folders (Flatpak exports included), else an SVG or pixmap
_icon_file() {
    local name="$1"
    [[ -z "$name" || "$name" == /* ]] && { printf '%s' "$name"; return; }
    local -a roots=("$HOME/.local/share/flatpak/exports/share/icons" /var/lib/flatpak/exports/share/icons
                    "$HOME/.local/share/icons" /usr/share/icons/hicolor /usr/share/pixmaps)
    local best="" best_size=0 f size
    while IFS= read -r f; do
        size="${f%/apps/*}"; size="${size##*/}"; size="${size%%x*}"
        [[ "$size" =~ ^[0-9]+$ ]] || size=1
        (( size > best_size )) && { best="$f"; best_size=$size; }
    done < <(find "${roots[@]}" -maxdepth 4 -name "$name.png" 2>/dev/null)
    [[ -z "$best" ]] && best=$(find "${roots[@]}" -maxdepth 4 \( -name "$name.svg" -o -name "$name.xpm" \) 2>/dev/null | head -1)
    printf '%s' "$best"
}
detect_custom_games() {
    local file="$CACHE_DIR/custom_games.json"
    [[ -f "$file" ]] || return 0
    local id name cmd icon flatpak dir
    # Unit separators, not tabs: read merges runs of tabs, so an empty field would shift the rest
    while IFS=$'\x1f' read -r id name cmd icon flatpak dir; do
        [[ -n "$id" && -n "$name" && "$cmd" != "[]" ]] || continue
        add_game "$id" "$name" "Custom" "$cmd" "" "$(_icon_file "$icon")" "$dir" "0" "0" "" "" "" "" "" "$flatpak"
    done < <(jq -r '.[]? | select(.id | startswith("custom_")) | [.id, .name, (.command // [] | tojson), (.icon // ""), (.flatpakId // ""), (.gameDir // "")]
                   | map(gsub("[\t\n\u001f]"; " ")) | join("\u001f")' "$file" 2>/dev/null)
}

# Main execution
detect_steam_games
detect_uninstalled_steam_games
detect_lutris_games
detect_custom_games

# Output JSON array — single jq invocation for the entire list
_output=""
if [[ ${#GAMES[@]} -eq 0 ]]; then
    _output="[]"
else
    _output=$(printf '%s\n' "${GAMES[@]}" | jq -R -s '
        split("\n") | map(select(length > 0)) | map(
            split("\t") | {
                id: .[0],
                name: .[1],
                source: .[2],
                launchCommand: (.[3] | fromjson),
                boxArt: .[4],
                icon: .[5],
                heroArt: .[6],
                gameDir: .[7],
                playtime: (.[8] | tonumber),
                lastPlayed: (.[9] | tonumber),
                buildId: (.[10] // "0" | tonumber),
                stateFlags: (.[11] // "4" | tonumber),
                protondbTier: (.[12] // ""),
                runner: (.[13] // ""),
                flatpakId: (.[14] // ""),
                lastUpdated: (.[15] // "0" | tonumber? // 0)
            }
        )
    ')
fi

# Steam's time played in the last two weeks (your account's, from the Web API), for the stats page's
# Recently played. Only with an API key; the stats page uses the launcher's own sessions otherwise
if [[ -n "${OWN_API_CACHE:-}" && -f "$OWN_API_CACHE" ]]; then
    _output=$(jq --slurpfile api "$OWN_API_CACHE" '
        ($api[0].response.games // [] | map({key: ("steam_" + (.appid | tostring)), value: (.playtime_2weeks // 0)}) | from_entries) as $p
        | map(. + {playtime2Weeks: ($p[.id] // 0)})' <<<"$_output" 2>/dev/null) || true
fi

# Enrich with partial box art detection
_output=$(echo "$_output" | _validate_art_paths)

# Cache output and fingerprint for delta detection
echo "$_output" > "$CACHED_OUTPUT"
echo "$_current_fp" > "$FINGERPRINT_FILE"
echo "$_output"
