"""
Shared App Store Connect API helpers for liiists ship scripts.

Config via env vars (falls back to defaults set by prior sessions):
  ASC_KEY_ID    — API Key ID (e.g. V79677KG8A)
  ASC_ISSUER_ID — Team's Issuer ID from ASC → Users and Access → Integrations
  ASC_KEY_PATH  — path to AuthKey_<KEY_ID>.p8

App ID is hard-coded (liiists is a single app; not worth env-varring).
"""
from __future__ import annotations

import base64
import json
import os
import time
from pathlib import Path
from typing import Any

import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

APP_ID = "6761671906"  # com.davidtingle.liiists

DEFAULT_KEY_ID = "V79677KG8A"
DEFAULT_ISSUER_ID = "b72fb376-0438-48ac-bf15-59c4dd7b3928"
DEFAULT_KEY_PATH = str(
    Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{DEFAULT_KEY_ID}.p8"
)

API_BASE = "https://api.appstoreconnect.apple.com"


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_jwt() -> str:
    """Build a short-lived ES256 JWT for the ASC API."""
    key_id = os.environ.get("ASC_KEY_ID", DEFAULT_KEY_ID)
    issuer_id = os.environ.get("ASC_ISSUER_ID", DEFAULT_ISSUER_ID)
    key_path = os.environ.get("ASC_KEY_PATH", DEFAULT_KEY_PATH)

    pem = Path(key_path).read_bytes()
    private_key = serialization.load_pem_private_key(pem, password=None)

    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,  # ASC max is 20 min
        "aud": "appstoreconnect-v1",
    }
    signing_input = f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}.{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    der_sig = private_key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der_sig)
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{_b64url(raw_sig)}"


def call(
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    query: dict[str, str] | None = None,
) -> dict[str, Any]:
    """Make an authenticated ASC API call, return JSON (or {} on 204)."""
    if query:
        path = f"{path}?{urllib.parse.urlencode(query)}"
    url = f"{API_BASE}{path}" if path.startswith("/") else path

    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {make_jwt()}")
    if body is not None:
        req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            if not raw:
                return {}
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {path} → {e.code}\n{detail}") from e
