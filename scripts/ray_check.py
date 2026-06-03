#!/usr/bin/env python3
"""Lightweight Ray sanity check used in Phase 1 local workflow.

Initialises a local Ray runtime (or reuses an existing one), prints the
dashboard URL, head node address, and discovered cluster resources, then shuts
down cleanly so `ray stop` is not required afterward. Exits with a non-zero
code if Ray cannot be initialised, helping CI or Make targets fail fast.
"""

from __future__ import annotations

import json
import sys
from typing import Any, Dict

import ray


def main() -> int:
    try:
        context = ray.init(ignore_reinit_error=True)
    except Exception as exc:  # pragma: no cover - defensive logging
        print(f"[ray-check] Failed to start Ray: {exc}", file=sys.stderr)
        return 1

    info: Dict[str, Any] = {
        "ray_version": ray.__version__,
        "dashboard_url": context.dashboard_url,
        "address": context.address_info.get("address") if context.address_info else None,
        "resources": ray.cluster_resources(),
    }

    print(json.dumps(info, indent=2, sort_keys=True))
    ray.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
