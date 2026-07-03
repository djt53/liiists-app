#!/usr/bin/env python3
"""
Submit a build to App Store review for liiists.

Usage:
    ./asc_submit.py <version> <build_number> [--whats-new-file path]

Example:
    ./asc_submit.py 1.3.2 68 --whats-new-file /tmp/whats_new.txt

Flow (6 calls):
  1. POST  /v1/appStoreVersions           create version, attach build inline
  2. GET   .../appStoreVersionLocalizations   find auto-created localization
  3. PATCH .../appStoreVersionLocalizations/{id}   set whatsNew
  4. POST  /v1/reviewSubmissions          create review submission
  5. POST  /v1/reviewSubmissionItems      link submission ↔ version
  6. PATCH /v1/reviewSubmissions/{id}     submitted: true
"""
from __future__ import annotations

import argparse
import sys

from asc_common import APP_ID, call


def find_build_id(build_version: str) -> str:
    resp = call(
        "GET",
        "/v1/builds",
        query={
            "filter[app]": APP_ID,
            "filter[version]": build_version,
            "limit": "5",
        },
    )
    builds = resp.get("data", [])
    if not builds:
        raise SystemExit(f"No build found with version={build_version}")
    # ASC returns builds sorted by uploaded-desc; take the newest
    build = builds[0]
    a = build["attributes"]
    if a.get("processingState") != "VALID":
        raise SystemExit(
            f"Build {build_version} state is {a.get('processingState')} (not VALID)"
        )
    return build["id"]


def create_version(version: str, build_id: str) -> str:
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version,
                "releaseType": "AFTER_APPROVAL",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
                "build": {"data": {"type": "builds", "id": build_id}},
            },
        }
    }
    resp = call("POST", "/v1/appStoreVersions", body=body)
    version_id = resp["data"]["id"]
    state = resp["data"]["attributes"].get("appStoreState")
    print(f"  ✓ created version {version} → {version_id} ({state})")
    return version_id


def find_localization(version_id: str) -> tuple[str, str]:
    resp = call(
        "GET",
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
    )
    locs = resp.get("data", [])
    if not locs:
        raise SystemExit("No localizations found on new version")
    loc = locs[0]
    locale = loc["attributes"]["locale"]
    return loc["id"], locale


def patch_whats_new(loc_id: str, whats_new: str) -> None:
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": loc_id,
            "attributes": {"whatsNew": whats_new},
        }
    }
    call("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", body=body)
    print(f"  ✓ set whatsNew ({len(whats_new)} chars)")


def create_review_submission() -> str:
    body = {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}}
            },
        }
    }
    resp = call("POST", "/v1/reviewSubmissions", body=body)
    sub_id = resp["data"]["id"]
    print(f"  ✓ created review submission → {sub_id}")
    return sub_id


def link_version_to_submission(sub_id: str, version_id: str) -> None:
    body = {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": sub_id}
                },
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                },
            },
        }
    }
    call("POST", "/v1/reviewSubmissionItems", body=body)
    print("  ✓ linked version to submission")


def submit(sub_id: str) -> str:
    body = {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True},
        }
    }
    resp = call("PATCH", f"/v1/reviewSubmissions/{sub_id}", body=body)
    state = resp["data"]["attributes"].get("state")
    print(f"  ✓ submitted → state: {state}")
    return state


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("version", help='e.g. "1.3.2"')
    p.add_argument("build", help='e.g. "68"')
    p.add_argument("--whats-new-file", required=True)
    args = p.parse_args()

    whats_new = open(args.whats_new_file, encoding="utf-8").read().strip()
    if not whats_new:
        raise SystemExit("whats-new file is empty")

    print(f"Submitting v{args.version} build {args.build} for review")
    print(f"App: {APP_ID}\n")

    build_id = find_build_id(args.build)
    print(f"  ✓ found build id {build_id}\n")

    version_id = create_version(args.version, build_id)
    loc_id, locale = find_localization(version_id)
    print(f"  ✓ localization {locale} → {loc_id}")
    patch_whats_new(loc_id, whats_new)
    sub_id = create_review_submission()
    link_version_to_submission(sub_id, version_id)
    state = submit(sub_id)

    print(f"\nDone. Version id: {version_id}")
    print(f"Submission id: {sub_id}")
    print(f"Submission state: {state}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
