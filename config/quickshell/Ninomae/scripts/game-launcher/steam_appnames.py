#!/usr/bin/env python3
"""Parse Steam's appinfo.vdf (V29 binary format) and output appid\tname for game entries.

Usage: steam_appnames.py <appinfo_path> <output_path>
Writes a TSV file: appid\tname (one per line, only type=Game/game/application)
"""
import struct
import sys

_UINT32 = struct.Struct("<I")
_UINT64 = struct.Struct("<Q")
_GAME_TYPES = frozenset(("game", "application"))

# Binary VDF value sizes by type byte (types with fixed-width values)
_FIXED_SIZES = {0x02: 4, 0x03: 4, 0x04: 4, 0x06: 4, 0x07: 8, 0x0A: 8}


def parse_appinfo(appinfo_path, output_path):
    with open(appinfo_path, "rb") as f:
        blob = f.read()

    # File header: magic(4) + universe(4) + string_table_offset(8) = 16 bytes
    magic = _UINT32.unpack_from(blob, 0)[0]
    if magic != 0x07564429:
        sys.exit(f"Unsupported appinfo.vdf version: 0x{magic:08X}")

    st_offset = _UINT64.unpack_from(blob, 8)[0]

    # Read string table: uint32 count + null-terminated strings
    st_strings = blob[st_offset + 4:].split(b"\x00")

    # Find key indices we need
    try:
        idx_common = st_strings.index(b"common")
        idx_name = st_strings.index(b"name")
        idx_type = st_strings.index(b"type")
    except ValueError as e:
        sys.exit(f"Missing key in string table: {e}")

    unpack_u32 = _UINT32.unpack_from
    lines = []
    pos = 16
    blob_len = st_offset  # entries end at string table

    while pos < blob_len - 8:
        appid = unpack_u32(blob, pos)[0]
        pos += 4
        if appid == 0:
            break
        size = unpack_u32(blob, pos)[0]
        pos += 4
        data = blob[pos:pos + size]
        pos += size

        # Skip 65-byte entry header (64 header + 1 format byte)
        name, app_type = _extract_name_type(
            data, 65, idx_common, idx_name, idx_type
        )

        if name and app_type and app_type.lower() in _GAME_TYPES:
            lines.append(f"{appid}\t{name}")

    with open(output_path, "w") as out:
        out.write("\n".join(lines) + "\n" if lines else "")


def _extract_name_type(data, pos, idx_common, idx_name, idx_type):
    """Scan top-level VDF for the 'common' subsection and extract name + type."""
    end = len(data)

    while pos < end:
        t = data[pos]
        if t == 0x08:
            break
        pos += 1
        key_idx = _UINT32.unpack_from(data, pos)[0]
        pos += 4

        if t == 0x00:  # SUBSECTION
            if key_idx == idx_common:
                return _parse_common(data, pos, end, idx_name, idx_type)
            pos = _skip_subsection(data, pos, end)
        elif t == 0x01:  # STRING
            pos = data.index(b"\x00", pos) + 1
        else:
            pos += _FIXED_SIZES.get(t, 0)

    return None, None


def _parse_common(data, pos, end, idx_name, idx_type):
    """Parse inside the 'common' subsection for name and type fields."""
    name = None
    app_type = None

    while pos < end:
        t = data[pos]
        if t == 0x08:
            break
        pos += 1
        key_idx = _UINT32.unpack_from(data, pos)[0]
        pos += 4

        if t == 0x00:  # nested subsection — skip
            pos = _skip_subsection(data, pos, end)
        elif t == 0x01:  # STRING
            nul = data.index(b"\x00", pos)
            if key_idx == idx_name:
                name = data[pos:nul].decode("utf-8", "replace")
            elif key_idx == idx_type:
                app_type = data[pos:nul].decode("utf-8", "replace")
            pos = nul + 1
        else:
            pos += _FIXED_SIZES.get(t, 0)

        if name and app_type:
            break

    return name, app_type


def _skip_subsection(data, pos, end):
    """Skip over a subsection (including nested ones)."""
    find_nul = data.index
    depth = 1
    while depth > 0 and pos < end:
        b = data[pos]
        pos += 1
        if b == 0x08:
            depth -= 1
        elif b == 0x00:
            pos += 4
            depth += 1
        elif b == 0x01 or b == 0x05:  # STRING/WIDESTRING
            pos = find_nul(b"\x00", pos + 4) + 1
        else:
            pos += 4 + _FIXED_SIZES.get(b, 0)
    return pos


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"Usage: {sys.argv[0]} <appinfo_path> <output_path>")
    parse_appinfo(sys.argv[1], sys.argv[2])