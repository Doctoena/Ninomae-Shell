#!/usr/bin/env python3
"""
Image colorfulness analysis and Material You scheme picker.
Optimized with better error handling and type hints.
"""
import sys
from typing import Literal

import cv2
import numpy as np

# Allowed scheme types
SCHEMES: list[str] = [
    "scheme-content",
    "scheme-expressive",
    "scheme-fidelity",
    "scheme-fruit-salad",
    "scheme-monochrome",
    "scheme-neutral",
    "scheme-rainbow",
    "scheme-tonal-spot",
]


def image_colorfulness(image: np.ndarray) -> float:
    """
    Calculate colorfulness using Hasler and Süsstrunk's metric.

    Args:
        image: Input image as numpy array

    Returns:
        Colorfulness score (higher = more colorful)
    """
    (B, G, R) = cv2.split(image.astype("float"))
    rg = np.absolute(R - G)
    yb = np.absolute(0.5 * (R + G) - B)
    std_rg, std_yb = np.std(rg), np.std(yb)
    mean_rg, mean_yb = np.mean(rg), np.mean(yb)
    return np.sqrt(std_rg**2 + std_yb**2) + (0.3 * np.sqrt(mean_rg**2 + mean_yb**2))


def pick_scheme(colorfulness: float) -> Literal[
    "scheme-content", "scheme-neutral", "scheme-tonal-spot"
]:
    """
    Pick Material You scheme based on colorfulness score.

    Args:
        colorfulness: Colorfulness score from image_colorfulness()

    Returns:
        Recommended scheme name
    """
    if colorfulness < 10:
        return "scheme-content"
    elif colorfulness < 20:
        return "scheme-content"
    elif colorfulness < 50:
        return "scheme-neutral"
    else:
        return "scheme-tonal-spot"


def main() -> None:
    """Main entry point."""
    colorfulness_mode = "--colorfulness" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--colorfulness"]

    if len(args) < 1:
        print("scheme-tonal-spot")
        sys.exit(1)

    img_path = args[0]
    img = cv2.imread(img_path)

    if img is None:
        print("scheme-tonal-spot")
        sys.exit(1)

    colorfulness = image_colorfulness(img)

    if colorfulness_mode:
        print(f"{colorfulness:.2f}")
    else:
        print(pick_scheme(colorfulness))


if __name__ == "__main__":
    main()
