#!/usr/bin/env python3
"""Utility to extract a single frame from a video for Serve smoke tests."""

from __future__ import annotations

import argparse
from pathlib import Path

import cv2


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path, help="Path to the source video (e.g. demo.mp4)")
    parser.add_argument(
        "--frame-index",
        type=int,
        default=0,
        help="Zero-based frame index to capture (default: 0)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("sample_frame.jpg"),
        help="Output image path (default: sample_frame.jpg in cwd)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.video.exists():
        raise SystemExit(f"Video not found: {args.video}")

    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        raise SystemExit(f"Could not open video: {args.video}")

    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, args.frame_index))
    success, frame = cap.read()
    cap.release()

    if not success or frame is None:
        raise SystemExit(f"Unable to read frame {args.frame_index} from {args.video}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(args.output), frame):
        raise SystemExit(f"Failed to write image to {args.output}")

    print(f"Saved frame {args.frame_index} from {args.video} to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
