#!/usr/bin/env python3
"""Saves part of a clip as a new clip, for the launcher's Clips page (the original is never changed).

Usage: export_clip.py trim <clip> <start s> <end s>
Writes "<name> (trim).mp4" next to the clip (then "(trim 2)"…), at the clip's own bitrate: looks the
same and isn't bigger. Prints "progress <0-1>" as it goes, then "done <bytes> <path>" or "error <message>".

Encodes on the GPU: VA-API (Intel/AMD) first, then NVENC, then libopenh264 in software. Fedora's
ffmpeg-free decodes H.264 in software only (libopenh264), which is most of the time it takes.
"""
import json
import os
import re
import subprocess
import sys


def say(*parts):
    print(*parts, flush=True)


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type,bit_rate:format=duration",
                          "-of", "json", path], capture_output=True, text=True).stdout
    j = json.loads(out or "{}")
    streams = j.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), {})
    return {
        "duration": float(j.get("format", {}).get("duration") or 0),
        "bitrate": int(video.get("bit_rate") or 0),
        "audio": any(s.get("codec_type") == "audio" for s in streams),
    }


def vaapi_device():
    """The render node of an Intel or AMD GPU, if there is one"""
    for name in sorted(os.listdir("/sys/class/drm")):
        if name.startswith("renderD"):
            try:
                driver = os.path.basename(os.readlink(f"/sys/class/drm/{name}/device/driver"))
            except OSError:
                continue
            if driver in ("i915", "xe", "amdgpu", "radeon"):
                return f"/dev/dri/{name}"
    return None


def video_encoders():
    out = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    return set(re.findall(r"^\s*V\S*\s+(\S+)", out, re.M))


def unique(path):
    """path, or "… (trim 2).mp4" and on when it's taken"""
    stem, ext = os.path.splitext(path)
    n, candidate = 1, path
    while os.path.exists(candidate):
        n += 1
        candidate = f"{stem[:-1]} {n}){ext}"
    return candidate


def trim(src, dst, start, end, video_kbps, audio):
    have = video_encoders()
    dev = vaapi_device() if "h264_vaapi" in have else None
    cmd = ["ffmpeg", "-v", "error", "-y", "-nostats", "-progress", "pipe:1"]
    if dev:
        cmd += ["-vaapi_device", dev]
    cmd += ["-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-i", src]  # Before -i: frame-accurate when re-encoding
    if dev:
        cmd += ["-vf", "format=nv12,hwupload", "-c:v", "h264_vaapi", "-rc_mode", "VBR"]
    elif "h264_nvenc" in have:
        cmd += ["-c:v", "h264_nvenc", "-rc", "vbr"]
    else:
        cmd += ["-c:v", "libopenh264"]
    cmd += ["-b:v", f"{video_kbps}k", "-maxrate", f"{int(video_kbps * 1.5)}k", "-bufsize", f"{video_kbps * 2}k"]
    cmd += ["-c:a", "aac", "-b:a", "192k"] if audio else ["-an"]
    # Made under a hidden name and renamed when done: the Clips page (list_clips.py) only lists finished ones
    part = os.path.join(os.path.dirname(dst), f".{os.path.basename(dst)}.part")
    cmd += ["-movflags", "+faststart", "-f", "mp4", part]  # faststart: plays while still downloading (Discord's embed)
    length = end - start
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for line in p.stdout:
        if line.startswith("out_time_us=") and length > 0:
            try:
                say("progress", f"{min(1.0, int(line.split('=')[1]) / 1e6 / length):.3f}")
            except ValueError:
                pass
    err = p.stderr.read().strip()
    if p.wait() != 0:
        try:
            os.remove(part)
        except OSError:
            pass
        raise RuntimeError(err.splitlines()[-1] if err else "ffmpeg failed")
    os.replace(part, dst)


def main():
    if len(sys.argv) < 5 or sys.argv[1] != "trim":
        raise RuntimeError("usage: export_clip.py trim <clip> <start s> <end s>")
    src = sys.argv[2]
    info = probe(src)
    start = max(0.0, float(sys.argv[3]))
    end = min(float(sys.argv[4]), info["duration"]) if info["duration"] > 0 else float(sys.argv[4])
    if end - start < 0.5:
        raise RuntimeError("The part to keep is too short")
    stem = os.path.splitext(os.path.basename(src))[0]
    dst = unique(os.path.join(os.path.dirname(src), f"{stem} (trim).mp4"))
    kbps = max(2000, (info["bitrate"] or 12_000_000) // 1000)
    trim(src, dst, start, end, kbps, info["audio"])
    say("done", os.path.getsize(dst), dst)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # The page shows it
        say("error", str(e).replace("\n", " "))
        sys.exit(1)
