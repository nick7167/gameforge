#!/usr/bin/env python3
"""App Store Connect API helper.

Generates a signed ES256 JWT from the App Store Connect API key and performs
a GET/POST/DELETE request against the App Store Connect API.

Required environment variables:
  APP_STORE_CONNECT_ISSUER_ID  - ASC issuer ID
  ASC_KEY_ID                   - the key ID (e.g. 2VNDM98D75)
  ASC_KEY_PATH                 - path to the .p8 private key file

Usage:
  asc-api.py GET  /v1/apps
  asc-api.py POST /v1/apps '{"data": {...}}'

Secrets are read from files/env only and are never printed.
"""

import base64
import json
import os
import sys
import time

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import load_pem_private_key

ISSUER = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
KEY_ID = os.environ["ASC_KEY_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]
BASE = "https://api.appstoreconnect.apple.com"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_token() -> str:
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    with open(KEY_PATH, "rb") as f:
        key = load_pem_private_key(f.read(), password=None)
    der_sig = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    # Convert DER ECDSA signature to raw r||s (64 bytes) required by JWT ES256
    # DER layout: 0x30 len 0x02 rlen <r> 0x02 slen <s>
    assert der_sig[0] == 0x30
    i = 2
    assert der_sig[i] == 0x02
    r_len = der_sig[i + 1]
    r = der_sig[i + 2 : i + 2 + r_len]
    i += 2 + r_len
    assert der_sig[i] == 0x02
    s_len = der_sig[i + 1]
    s = der_sig[i + 2 : i + 2 + s_len]
    r = r.lstrip(b"\x00")
    s = s.lstrip(b"\x00")
    raw = r.rjust(32, b"\x00") + s.rjust(32, b"\x00")
    assert len(raw) == 64
    return f"{signing_input}.{b64url(raw)}"


def main() -> int:
    method, path = sys.argv[1], sys.argv[2]
    body = sys.argv[3] if len(sys.argv) > 3 else None
    import urllib.request
    import urllib.error

    req = urllib.request.Request(
        BASE + path,
        data=body.encode() if body else None,
        method=method,
        headers={
            "Authorization": f"Bearer {make_token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            print(resp.status)
            print(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(e.code)
        print(e.read().decode())
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
