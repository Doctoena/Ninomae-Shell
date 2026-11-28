#!/usr/bin/env python3
"""Finds pictures and panels in a screenshot, for the screenshot tool (modules/regionSelector) to offer as
click targets. OpenCV's selective search on a small copy of the image (fast), then boxes that mostly cover
each other are merged. Prints JSON in image pixels: [{"x", "y", "width", "height"}], or with --hyprctl
[{"at": [x, y], "size": [w, h]}] like hyprctl's windows. Run through find-regions-venv.sh (OpenCV is in
the shell's venv).
"""
import argparse
import json
import sys

import cv2


def iou(a, b):
    """Intersection over union of two boxes"""
    x1, y1 = max(a["x"], b["x"]), max(a["y"], b["y"])
    x2 = min(a["x"] + a["width"], b["x"] + b["width"])
    y2 = min(a["y"] + a["height"], b["y"] + b["height"])
    inter = max(0, x2 - x1) * max(0, y2 - y1)
    union = a["width"] * a["height"] + b["width"] * b["height"] - inter
    return inter / union if union > 0 else 0


def non_max_suppression(regions, threshold=0.7):
    """Largest first; drops boxes that mostly cover one already kept"""
    keep = []
    for r in sorted(regions, key=lambda r: r["width"] * r["height"], reverse=True):
        if all(iou(r, k) < threshold for k in keep):
            keep.append(r)
    return keep


def find_regions(path, min_width, min_height, max_width, max_height, k, min_size, sigma, resize):
    image = cv2.imread(path)
    if image is None:
        sys.exit(f"Could not load {path}")
    height, width = image.shape[:2]
    small = cv2.resize(image, (int(width * resize), int(height * resize)), interpolation=cv2.INTER_AREA)
    ss = cv2.ximgproc.segmentation.createSelectiveSearchSegmentation()
    ss.setBaseImage(small)
    ss.switchToSelectiveSearchFast(k, min_size, sigma)
    regions = []
    for x, y, w, h in ss.process():
        x, y, w, h = int(x / resize), int(y / resize), int(w / resize), int(h / resize)
        if (x, y, w, h) == (0, 0, width, height):
            continue  # The whole image
        if min_width < w < (max_width or w + 1) and min_height < h < (max_height or h + 1):
            regions.append({"x": x, "y": y, "width": w, "height": h})
    return non_max_suppression(regions), image


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("-i", "--image", required=True, help="the screenshot")
    parser.add_argument("--min-width", type=int, default=200, help="smallest box, in pixels (default 200)")
    parser.add_argument("--min-height", type=int, default=100, help="(default 100)")
    parser.add_argument("--max-width", type=int, help="largest box, in pixels (default: no limit)")
    parser.add_argument("--max-height", type=int)
    parser.add_argument("--k", type=int, default=3000, help="segmentation k (default 3000)")
    parser.add_argument("--min-size", type=int, default=50, help="segmentation min_size (default 50)")
    parser.add_argument("--sigma", type=float, default=0.6, help="segmentation sigma (default 0.6)")
    parser.add_argument("--resize-factor", type=float, default=0.1, help="searched at this size (default 0.1)")
    parser.add_argument("--hyprctl", action="store_true", help='output as {"at": [x, y], "size": [w, h]}')
    parser.add_argument("-do", "--debug-output", help="also save the image with the boxes drawn on it here")
    args = parser.parse_args()

    regions, image = find_regions(args.image, args.min_width, args.min_height, args.max_width, args.max_height,
                                  args.k, args.min_size, args.sigma, args.resize_factor)
    if args.debug_output:
        for r in regions:
            cv2.rectangle(image, (r["x"], r["y"]), (r["x"] + r["width"], r["y"] + r["height"]), (0, 0, 255), 2)
        cv2.imwrite(args.debug_output, image)
    if args.hyprctl:
        regions = [{"at": [r["x"], r["y"]], "size": [r["width"], r["height"]]} for r in regions]
    print(json.dumps(regions))


if __name__ == "__main__":
    main()
