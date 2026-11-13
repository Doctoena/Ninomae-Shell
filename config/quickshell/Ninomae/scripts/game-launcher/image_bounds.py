#!/usr/bin/env python3
"""The part of a picture that isn't see-through: "x y width height" in its own pixels, or nothing when it has
no transparency (or can't be read). Game logos often sit in a bigger transparent canvas (Warframe's: 22 px
above, 64 below), so laid out by their box they look off centre; GameLauncherService.logoClip() crops them to
this. Runs with the shell's Python (~/.local/state/quickshell/.venv, which has Pillow).

Usage: image_bounds.py <file>
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit(0)


def main():
    try:
        with Image.open(sys.argv[1]) as im:
            if "A" not in im.getbands():
                return
            # Nearly clear pixels (soft shadows, anti-aliasing haze) don't count
            box = im.getchannel("A").point(lambda a: 255 if a > 12 else 0).getbbox()
            if box and box != (0, 0, im.width, im.height):
                print(box[0], box[1], box[2] - box[0], box[3] - box[1])
    except (OSError, IndexError):
        pass


if __name__ == "__main__":
    main()
