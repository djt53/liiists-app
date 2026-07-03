#!/usr/bin/env python3
"""
ASC status check for liiists.

Usage:
    ./asc_query.py            # summary of latest builds + versions
    ./asc_query.py builds     # last 10 builds w/ processing state
    ./asc_query.py versions   # last 5 App Store versions w/ review state
    ./asc_query.py submissions  # pending review submissions

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (see asc_common.py)
"""
from __future__ import annotations

import sys

from asc_common import APP_ID, call


def fmt_build(b: dict) -> str:
    a = b["attributes"]
    return (
        f"  build {a.get('version'):>4} — {a.get('processingState')} "
        f"(uploaded {a.get('uploadedDate', '')[:19]})"
    )


def show_builds(limit: int = 10) -> list[dict]:
    resp = call(
        "GET",
        "/v1/builds",
        query={
            "filter[app]": APP_ID,
            "sort": "-version",
            "limit": str(limit),
        },
    )
    builds = resp.get("data", [])
    print(f"Last {len(builds)} builds:")
    for b in builds:
        print(fmt_build(b))
    return builds


def show_versions(limit: int = 5) -> list[dict]:
    resp = call(
        "GET",
        f"/v1/apps/{APP_ID}/appStoreVersions",
        query={"limit": str(limit)},
    )
    versions = resp.get("data", [])
    print(f"\nLast {len(versions)} App Store versions:")
    for v in versions:
        a = v["attributes"]
        print(
            f"  v{a.get('versionString'):<8} — {a.get('appStoreState')} "
            f"(release: {a.get('releaseType')})"
        )
    return versions


def show_submissions() -> None:
    resp = call(
        "GET",
        f"/v1/apps/{APP_ID}/reviewSubmissions",
        query={"limit": "5"},
    )
    subs = resp.get("data", [])
    print(f"\nLast {len(subs)} review submissions:")
    for s in subs:
        a = s["attributes"]
        print(f"  {s['id']} — {a.get('state')} (platform: {a.get('platform')})")


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd in ("status", "builds"):
        show_builds()
    if cmd in ("status", "versions"):
        show_versions()
    if cmd in ("status", "submissions"):
        show_submissions()
    return 0


if __name__ == "__main__":
    sys.exit(main())
