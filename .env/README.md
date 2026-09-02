# .env/ — secrets and credentials (NEVER COMMITTED)

Everything in this folder is gitignored via `.env/*`. It exists so the repo
scripts have one predictable place to find credentials on any machine.

| File | Contents | Used by |
|---|---|---|
| `codemagic.env` | `CODEMAGIC_API_TOKEN` | `scripts/trigger-testflight.sh`, Codemagic API calls |
| `asc.env` | `APP_STORE_CONNECT_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_PATH` | `scripts/asc-api.py`, Codemagic signing bootstrap |
| `keys/` | `.p8` private keys (e.g. `AuthKey_2VNDM98D75.p8`) | `scripts/asc-api.py` |

## One-time setup on a new machine

1. Copy the API key file here (from wherever it lives, e.g. the old Mac's
   `~/Desktop/vigtigt/`):
   ```bash
   cp "/path/to/AuthKey_2VNDM98D75 ....p8" .env/keys/AuthKey_2VNDM98D75.p8
   ```
2. Paste the tokens into `codemagic.env` and `asc.env`.
3. Verify:
   ```bash
   set -a; source .env/codemagic.env; source .env/asc.env; set +a
   python3 scripts/asc-api.py GET "/v1/apps"   # should list the AdrezGame app
   ```

Never print, commit, or copy these values into logs. `.gitignore` enforces
the ignore; keep it that way.
