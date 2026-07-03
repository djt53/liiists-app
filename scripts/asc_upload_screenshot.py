#!/usr/bin/env python3
"""
Upload one screenshot to an App Store version localization.

Usage:
    ./asc_upload_screenshot.py <localization_id> <display_type> <path>

Display types (common):
    APP_WATCH_SERIES_4        368 x 448   (44mm SE/4/5/6/SE2)
    APP_WATCH_SERIES_7        396 x 484   (45mm S7-9/SE3)
    APP_WATCH_ULTRA           410 x 502   (49mm Ultra)
    APP_IPHONE_67             1290 x 2796 (6.7" 15/16 Pro Max)

Flow:
  1. POST /v1/appScreenshotSets       — create set (per size class × locale)
  2. POST /v1/appScreenshots          — reserve upload, get uploadOperations
  3. PUT  each uploadOperation URL    — send file bytes
  4. PATCH /v1/appScreenshots/{id}    — mark uploaded: true, submit checksum
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

from asc_common import call, make_jwt


def find_or_create_screenshot_set(loc_id: str, display_type: str) -> str:
    # Reuse existing set if one already exists (rerun-safe).
    resp = call(
        "GET",
        f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
    )
    for s in resp.get("data", []):
        if s["attributes"].get("screenshotDisplayType") == display_type:
            return s["id"]

    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": loc_id,
                    }
                }
            },
        }
    }
    r = call("POST", "/v1/appScreenshotSets", body=body)
    return r["data"]["id"]


def reserve(set_id: str, path: Path) -> dict:
    body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileSize": path.stat().st_size,
                "fileName": path.name,
            },
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            },
        }
    }
    return call("POST", "/v1/appScreenshots", body=body)["data"]


def upload_bytes(op: dict, data: bytes) -> None:
    url = op["url"]
    offset = op["offset"]
    length = op["length"]
    chunk = data[offset : offset + length]
    req = urllib.request.Request(url, data=chunk, method=op["method"])
    for h in op["requestHeaders"]:
        req.add_header(h["name"], h["value"])
    try:
        with urllib.request.urlopen(req) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"PUT {url} → {e.code}\n{e.read().decode()}") from e


def commit(screenshot_id: str, data: bytes) -> None:
    checksum = hashlib.md5(data).hexdigest()
    body = {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
        }
    }
    call("PATCH", f"/v1/appScreenshots/{screenshot_id}", body=body)


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    loc_id, display_type, path_str = sys.argv[1], sys.argv[2], sys.argv[3]
    path = Path(path_str)
    if not path.exists():
        raise SystemExit(f"file not found: {path}")

    data = path.read_bytes()
    print(f"Uploading {path.name} ({len(data)} bytes) as {display_type}")

    set_id = find_or_create_screenshot_set(loc_id, display_type)
    print(f"  ✓ screenshot set {set_id}")

    reserved = reserve(set_id, path)
    screenshot_id = reserved["id"]
    ops = reserved["attributes"]["uploadOperations"]
    print(f"  ✓ reserved {screenshot_id} ({len(ops)} upload op(s))")

    for i, op in enumerate(ops):
        upload_bytes(op, data)
        print(f"    ✓ chunk {i+1}/{len(ops)}")

    commit(screenshot_id, data)
    print(f"  ✓ committed (md5={hashlib.md5(data).hexdigest()[:12]}…)")
    print(f"\nDone. Screenshot id: {screenshot_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
