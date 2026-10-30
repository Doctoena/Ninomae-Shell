#!/usr/bin/env python3
"""Uploads screenshots and clips to an Immich server (the launcher's Captures sheet), into an album named
after the game (made if missing). Prints JSON: {"uploaded": n, "duplicates": n, "failed": n,
"album": bool, "error": "…"}; duplicates are ones the server already has (it matches by checksum):
asked first (bulk-upload-check), so those aren't sent again, but still go in the album. The rest
go up a few at a time.

Usage: IMMICH_API_KEY=… immich_upload.py <server url> <game name or ""> <file>...
  The key comes in the environment, not as an argument: any process can read those (ps). It needs
  the asset.upload permission, and album.read, album.create and albumAsset.create for the album
  (without those the screenshots are still uploaded, just not put in it). Immich 3.x API.
"""
import hashlib
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

UPLOADS_AT_ONCE = 4


def request(base, key, method, path, body=None, content_type="application/json"):
    data = json.dumps(body).encode() if content_type == "application/json" and body is not None else body
    req = urllib.request.Request(base + "/api" + path, data=data, method=method,
                                 headers={"x-api-key": key, "Accept": "application/json",
                                          # Cloudflare (in front of many self-hosted servers) refuses Python's own (error 1010)
                                          "User-Agent": "Ninomae-Shell",
                                          **({"Content-Type": content_type} if data is not None else {})})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read() or b"null")


def upload(base, key, path):
    """(asset id, "created" | "duplicate")."""
    when = datetime.fromtimestamp(os.path.getmtime(path), timezone.utc).isoformat().replace("+00:00", "Z")
    # It goes in quotes in the form's headers: no quote or line break may end them early
    name = os.path.basename(path).replace('"', "%22").replace("\r", "").replace("\n", "")
    boundary = uuid.uuid4().hex
    parts = []
    for field, value in (("fileCreatedAt", when), ("fileModifiedAt", when), ("filename", name)):
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"\r\n\r\n{value}\r\n'.encode())
    with open(path, "rb") as f:
        content = f.read()
    mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="assetData"; filename="{name}"\r\n'
                 f'Content-Type: {mime}\r\n\r\n'.encode() + content + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    r = request(base, key, "POST", "/assets", b"".join(parts), f"multipart/form-data; boundary={boundary}")
    return r["id"], r["status"]


def already_there(base, key, files):
    """{path: asset id} of the files the server already has, by SHA1; {} when it can't say. A refused
    key raises: it's the first request, so nothing has been sent yet"""
    items = []
    for path in files:
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        items.append({"id": path, "checksum": h.hexdigest()})
    try:
        results = request(base, key, "POST", "/assets/bulk-upload-check", {"assets": items})["results"]
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            raise
        return {}
    except Exception:
        return {}
    return {r["id"]: r["assetId"] for r in results if r.get("action") == "reject" and r.get("assetId")}


def add_to_album(base, key, name, ids):
    query = urllib.parse.urlencode({"name": name, "isOwned": "true"})
    albums = request(base, key, "GET", "/albums?" + query)
    album = next((a for a in albums if a.get("albumName") == name), None)
    if album is None:
        request(base, key, "POST", "/albums", {"albumName": name, "assetIds": ids})
    else:
        request(base, key, "PUT", f"/albums/{album['id']}/assets", {"ids": ids})


def why(e):
    if isinstance(e, urllib.error.HTTPError):
        try:
            message = json.loads(e.read()).get("message")
        except Exception:
            message = None
        if isinstance(message, list):
            message = "; ".join(map(str, message))
        return f"{e.code}: {message or e.reason}"
    if isinstance(e, urllib.error.URLError):
        return str(e.reason)
    return str(e)


def main():
    base, game, files = sys.argv[1].rstrip("/"), sys.argv[2].strip(), sys.argv[3:]
    key = os.environ.get("IMMICH_API_KEY", "")
    out = {"uploaded": 0, "duplicates": 0, "failed": 0, "album": False, "error": ""}
    if not key or not base:
        out["error"] = "Immich server or API key not set"
        out["failed"] = len(files)
        print(json.dumps(out))
        return
    files = list(dict.fromkeys(files))
    try:
        known = already_there(base, key, files)
    except urllib.error.HTTPError as e:  # The key is wrong: every upload would fail too
        out["error"], out["failed"] = why(e), len(files)
        print(json.dumps(out))
        return
    ids = list(known.values())
    out["duplicates"] = len(known)

    def send(path):
        try:
            return upload(base, key, path), None
        except Exception as e:
            return None, why(e)

    with ThreadPoolExecutor(max_workers=UPLOADS_AT_ONCE) as pool:
        for result, error in pool.map(send, [p for p in files if p not in known]):
            if error:
                out["failed"] += 1
                out["error"] = error
            else:
                ids.append(result[0])
                out["uploaded" if result[1] == "created" else "duplicates"] += 1
    if game and ids:
        try:
            add_to_album(base, key, game, ids)
            out["album"] = True
        except Exception as e:
            out["error"] = out["error"] or "Album: " + why(e)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
