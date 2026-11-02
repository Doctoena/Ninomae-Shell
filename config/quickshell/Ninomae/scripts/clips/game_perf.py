#!/usr/bin/env python3
"""For the in-game overlay's Performance, while a game runs: which GPU it draws on, and its frame rate.

Every 2 s prints a JSON line:
  {"pids": [the game's processes], "gpu": "intel" | "amd" | "nvidia" | "", "integrated": bool,
   "busy": 0–1 or -1, "fps": number or -1, "fpsAvg": …, "fpsLow": …}

The GPU: the kernel says, for Intel and AMD, how long each of a program's GPU clients kept the GPU busy
(/proc/<pid>/fdinfo, drm-engine-*). A game doing any work there draws on that GPU, and busy is its share of it.
NVIDIA's driver doesn't say, and every Vulkan program opens /dev/nvidia* just to list the GPUs: a game holding
it and busy on no other GPU is on the NVIDIA one (busy -1, the overlay has nvidia-smi's).

The frame rate: MangoHud, when the game runs with it, writes a log as it goes (MangoHud.conf: output_folder,
autostart_log, log_interval). The newest one written since the session started is the game's: the latest
fps, the session's average, and its 1% low (the lowest 1 % of the samples), past its first 2 s. -1 without one. Logs older than
two days are deleted.

Usage: game_perf.py <MangoHud log folder> <session start, s since the epoch> <matcher> […]
(the matchers as game_pids.py's)
"""
import bisect
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from game_pids import game_pids  # noqa: E402

INTERVAL = 2.0
SKIP = 8  # A log's first samples (2 s at MangoHud.conf's log_interval=250): the game's first, near-0 frames
PIDS_EVERY = 5  # Ticks between looking for the game's processes, and their GPU handles, again
VENDORS = {"i915": "intel", "xe": "intel", "amdgpu": "amd"}


def gpu_handles(pids):
    """The game's open GPU devices: its DRM ones as fdinfo paths, and whether it holds an NVIDIA one"""
    paths, nvidia = [], False
    for pid in pids:
        try:
            fds = os.listdir(f"/proc/{pid}/fd")
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("/dev/dri/"):
                paths.append(f"/proc/{pid}/fdinfo/{fd}")
            elif re.fullmatch(r"/dev/nvidia\d+", target):
                nvidia = True
    return paths, nvidia


def gpu_clients(paths):
    """{(pdev, client id): (driver, busy ns, has local memory)} of the game's Intel and AMD GPU clients"""
    clients = {}
    for path in paths:
        try:
            with open(path) as f:
                info = dict(line.split(":", 1) for line in f if ":" in line)
        except OSError:
            continue
        driver = info.get("drm-driver", "").strip()
        if driver not in VENDORS:
            continue
        busy = sum(int(v.split()[0]) for k, v in info.items()
                   if k.startswith("drm-engine-") and not k.startswith("drm-engine-capacity") and v.split()[0].isdigit())
        local = any(k.startswith(("drm-resident-local", "drm-memory-vram")) and not v.strip().startswith("0") for k, v in info.items())
        clients[(info.get("drm-pdev", "").strip(), info.get("drm-client-id", "").strip())] = (driver, busy, local)
    return clients


def integrated(driver, pdev, local):
    """An iGPU: Intel's without memory of its own (Arc has some), AMD's with under 2 GiB of VRAM (a carve-out)"""
    if driver == "amdgpu":
        try:
            with open(f"/sys/bus/pci/devices/{pdev}/mem_info_vram_total") as f:
                return int(f.read()) < 2 << 30
        except (OSError, ValueError):
            return False
    return not local


class FpsLog:
    """The game's MangoHud log, read as it grows"""

    def __init__(self, folder, since):
        self.folder, self.since = folder, since
        self.path, self.offset, self.column, self.partial, self.skipped = None, 0, -1, "", 0
        self.samples, self.ordered, self.total = [], [], 0.0  # As they came, and kept sorted for the 1% low

    def find(self):
        try:
            names = [n for n in os.listdir(self.folder) if n.endswith(".csv") and not n.endswith("_summary.csv")]
        except OSError:
            return None
        paths = [os.path.join(self.folder, n) for n in names]
        paths = [p for p in paths if os.path.getmtime(p) >= self.since]
        return max(paths, key=os.path.getmtime) if paths else None

    def read(self):
        newest = self.find()
        if newest and newest != self.path:  # A new log: the game restarted, or this is the first
            self.path, self.offset, self.column, self.partial, self.skipped = newest, 0, -1, "", 0
            self.samples, self.ordered, self.total = [], [], 0.0
        if not self.path:
            return
        try:
            with open(self.path) as f:
                f.seek(self.offset)
                text = f.read()
                self.offset = f.tell()
        except OSError:
            return
        lines = (self.partial + text).split("\n")
        self.partial = lines.pop()  # Not finished yet
        for line in lines:
            cells = line.split(",")
            if self.column < 0:
                if "fps" in cells:  # The column names, after the system's line
                    self.column = cells.index("fps")
                continue
            try:
                fps = float(cells[self.column])
            except (IndexError, ValueError):
                continue
            if self.skipped < SKIP:
                self.skipped += 1
            elif fps > 0:
                self.samples.append(fps)
                bisect.insort(self.ordered, fps)
                self.total += fps

    def stats(self):
        if not self.samples:
            return -1, -1, -1
        low = self.ordered[: max(1, len(self.ordered) // 100)]
        return self.samples[-1], self.total / len(self.samples), sum(low) / len(low)


def clean(folder):
    cutoff = time.time() - 2 * 86400
    try:
        for name in os.listdir(folder):
            path = os.path.join(folder, name)
            if name.endswith(".csv") and os.path.getmtime(path) < cutoff:
                os.remove(path)
    except OSError:
        pass


def main():
    folder, since, matchers = os.path.expanduser(sys.argv[1]), float(sys.argv[2]), sys.argv[3:]
    os.makedirs(folder, exist_ok=True)
    clean(folder)
    log = FpsLog(folder, since - 5)
    pids, handles, nvidia, before, tick = [], [], False, {}, 0
    while True:
        if matchers and (tick % PIDS_EVERY == 0 or not handles):  # Every look until the game has opened a GPU
            pids = game_pids(matchers)
            handles, nvidia = gpu_handles(pids)
        tick += 1
        clients = gpu_clients(handles)
        # The GPU the game kept busiest since the last look
        gpu, busiest, igpu = "", 0.0, False
        for key, (driver, busy, local) in clients.items():
            share = (busy - before[key][1]) / (INTERVAL * 1e9) if key in before else 0.0
            if share > busiest:
                gpu, busiest, igpu = VENDORS[driver], share, integrated(driver, key[0], local)
        before = clients
        if busiest < 0.002:  # Idle on those: NVIDIA's, if it has one open
            gpu, busiest, igpu = ("nvidia", -1, False) if nvidia else ("", -1, False)
        log.read()
        fps, avg, low = log.stats()
        print(json.dumps({"pids": pids, "gpu": gpu, "integrated": igpu, "busy": round(min(1.0, busiest), 3) if busiest >= 0 else -1,
                          "fps": round(fps, 1), "fpsAvg": round(avg, 1), "fpsLow": round(low, 1)}), flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
