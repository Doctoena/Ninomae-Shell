#!/usr/bin/env python3
"""Pauses and resumes Steam's downloads, through the same calls as the buttons in Steam's Downloads page.

  steam_control.py resume <appid>     → starts it now, ahead of the rest (Steam's "Move to top"); also the retry
  steam_control.py remove <appid>     → takes it off the download queue (Steam's ✕); it updates later, or when played
  steam_control.py remove-and-resume <appid>
                                      → the same for the paused one at the queue's head: the rest go again
  steam_control.py pause-all | resume-all

Steam's window is a Chromium page, and its buttons call SteamClient.Downloads.* in Steam's main page
("SharedJSContext"). With Settings → Games → "Pause and resume from the launcher" on, Steam starts with
-cef-enable-debugging, which opens its debugging port on localhost only, and this runs the call there
over the Chrome DevTools protocol. Errors (JSON "error"):
off (no port: the setting is off, or Steam isn't running), no-page (Steam's page isn't there yet),
failed (Steam refused the call, as when Valve renames it).
"""
import base64, json, os, socket, struct, sys, urllib.request

PORT = 8080
LOCAL_CLIENT = "0"  # Steam's id for this PC (the Downloads page can also show another PC's downloads)


def targets():
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # Straight to localhost, never a proxy
    with opener.open(f"http://127.0.0.1:{PORT}/json", timeout=2) as r:
        return json.load(r)


class WebSocket:
    """Just enough of a WebSocket client (RFC 6455) for a few DevTools messages: text frames, masked."""

    def __init__(self, url):
        rest = url.split("://", 1)[1]
        hostport, path = rest.split("/", 1)
        host, port = hostport.rsplit(":", 1)
        self.sock = socket.create_connection((host, int(port)), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1024)
            if not chunk:
                raise OSError("closed during handshake")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise OSError("handshake refused")
        self.buf = head.split(b"\r\n\r\n", 1)[1]

    def send(self, text):
        data = text.encode()
        mask = os.urandom(4)
        n = len(data)
        header = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n)
                                  if n < 65536 else bytes([0x80 | 127]) + struct.pack(">Q", n))
        self.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise OSError("closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        message = b""
        while True:
            b0, b1 = self._read(2)
            n = b1 & 0x7F
            if n == 126: n = struct.unpack(">H", self._read(2))[0]
            elif n == 127: n = struct.unpack(">Q", self._read(8))[0]
            payload = self._read(n)
            if b0 & 0x0F in (0x1, 0x0):
                message += payload
                if b0 & 0x80:
                    return message.decode(errors="replace")

    def close(self):
        try: self.sock.close()
        except OSError: pass


def value(expression):
    """Runs expression in Steam's main page (awaited if it's a promise): (its value, None), or (None, error)"""
    try:
        pages = targets()
    except OSError:
        return None, "off"
    page = next((t for t in pages if t.get("title") == "SharedJSContext" and t.get("webSocketDebuggerUrl")), None)
    if not page:
        return None, "no-page"
    try:
        ws = WebSocket(page["webSocketDebuggerUrl"])
    except OSError:
        return None, "off"
    try:
        ws.send(json.dumps({"id": 1, "method": "Runtime.evaluate",
                            "params": {"expression": expression, "awaitPromise": True, "returnByValue": True}}))
        while True:
            reply = json.loads(ws.recv())
            if reply.get("id") == 1:
                break
    finally:
        ws.close()
    result = reply.get("result", {})
    if "error" in reply or "exceptionDetails" in result:
        return None, "failed"
    return result.get("result", {}).get("value"), None


def evaluate(expression):
    """Runs expression, which says true when it worked; (ok, error)"""
    result, err = value(expression)
    return result is True, err or (None if result is True else "failed")


def call(fn, *args):
    """SteamClient.Downloads.<fn>(args…, this PC), true if Steam has it and took the call"""
    arglist = ", ".join(json.dumps(a) for a in (*args, LOCAL_CLIENT))
    return evaluate(f"(async () => {{ const d = globalThis.SteamClient?.Downloads;"
                    f" if (typeof d?.{fn} !== 'function') return false; await d.{fn}({arglist}); return true; }})()")


def main():
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "resume" and a[1].isdigit():
        ok, err = call("ResumeAppUpdate", int(a[1]))
    elif len(a) == 2 and a[0] in ("remove", "remove-and-resume") and a[1].isdigit():
        # As Steam's ✕: off the list, and for the paused one at the queue's head, the rest going again
        resume = f"await d.EnableAllDownloads(true, {json.dumps(LOCAL_CLIENT)});" if a[0] == "remove-and-resume" else ""
        ok, err = evaluate(f"""(async () => {{ const d = globalThis.SteamClient?.Downloads;
            if (typeof d?.RemoveFromDownloadList !== 'function') return false;
            await d.RemoveFromDownloadList({int(a[1])}, {json.dumps(LOCAL_CLIENT)}); {resume} return true; }})()""")
    elif a in (["pause-all"], ["resume-all"]):
        ok, err = call("EnableAllDownloads", a[0] == "resume-all")
    else:
        print(__doc__)
        return 1
    print(json.dumps({"ok": ok, "error": err}))
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except OSError as e:
        print(json.dumps({"ok": False, "error": "off" if isinstance(e, ConnectionRefusedError) else "failed"}))
        sys.exit(1)
