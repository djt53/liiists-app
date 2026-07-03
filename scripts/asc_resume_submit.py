#!/usr/bin/env python3
"""
Resume a partially-created review submission (after fixing an ENTITY_STATE_INVALID
blocker like a missing screenshot).

Usage:
    ./asc_resume_submit.py <version_id> <submission_id>
"""
from __future__ import annotations

import sys

from asc_common import call


def link_and_submit(version_id: str, sub_id: str) -> None:
    link_body = {
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
    call("POST", "/v1/reviewSubmissionItems", body=link_body)
    print("  ✓ linked version to submission")

    submit_body = {
        "data": {
            "type": "reviewSubmissions",
            "id": sub_id,
            "attributes": {"submitted": True},
        }
    }
    resp = call("PATCH", f"/v1/reviewSubmissions/{sub_id}", body=submit_body)
    state = resp["data"]["attributes"].get("state")
    print(f"  ✓ submitted → state: {state}")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    version_id, sub_id = sys.argv[1], sys.argv[2]
    link_and_submit(version_id, sub_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
