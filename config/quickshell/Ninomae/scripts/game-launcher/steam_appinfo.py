"""Reader for Steam's appcache/appinfo.vdf (binary KeyValues, format 28/29), shared by the launcher scripts."""
import os, struct

APPINFO = os.path.expanduser("~/.local/share/Steam/appcache/appinfo.vdf")

def read_kv(buf, pos, strings):
    """Binary KeyValues → dict. Keys are inline strings (v28) or string-table indices (v29)."""
    out = {}
    while True:
        t = buf[pos]; pos += 1
        if t == 0x08:
            return out, pos
        if strings is None:
            end = buf.index(b"\0", pos); key = buf[pos:end].decode("utf-8", "replace"); pos = end + 1
        else:
            key = strings[struct.unpack_from("<I", buf, pos)[0]]; pos += 4
        if t == 0x00:
            out[key], pos = read_kv(buf, pos, strings)
        elif t == 0x01:
            end = buf.index(b"\0", pos); out[key] = buf[pos:end].decode("utf-8", "replace"); pos = end + 1
        elif t in (0x02, 0x03, 0x04, 0x06):
            out[key] = struct.unpack_from("<i", buf, pos)[0]; pos += 4
        elif t in (0x07, 0x0A):
            out[key] = struct.unpack_from("<Q" if t == 0x07 else "<q", buf, pos)[0]; pos += 8
        else:
            raise ValueError(f"unknown KV type {t:#x}")

def apps(appids, path=APPINFO):
    """{appid: its "appinfo" dict} for the wanted appids; only those entries are parsed."""
    wanted, found = set(appids), {}
    buf = open(path, "rb").read()
    pos, strings = 8, None
    if struct.unpack_from("<I", buf, 0)[0] & 0xFF >= 0x29:
        table = struct.unpack_from("<Q", buf, 8)[0]; pos = 16
        strings, p = [], table + 4
        for _ in range(struct.unpack_from("<I", buf, table)[0]):
            end = buf.index(b"\0", p); strings.append(buf[p:end].decode("utf-8", "replace")); p = end + 1
    while pos + 8 <= len(buf) and wanted:
        aid, size = struct.unpack_from("<II", buf, pos)
        if aid == 0:
            break
        if aid in wanted:
            wanted.discard(aid)
            try:
                # infostate, last_updated, pics token, sha1, change number, binary sha1 → 60 bytes
                found[aid] = read_kv(buf, pos + 8 + 60, strings)[0].get("appinfo") or {}
            except (ValueError, IndexError, struct.error):
                pass
        pos += 8 + size
    return found
