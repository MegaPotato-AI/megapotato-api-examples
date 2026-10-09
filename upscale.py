"""Upscale one photo with the MegaPotato API: upload it, wait for the result, download it.

Usage:  python upscale.py photo.jpg [scale]     scale: 1 (refine, same size), 2, 4 (default) or 8
Needs:  Python 3.9+, requests (pip install -r requirements.txt),
        and your API key in the MEGAPOTATO_API_KEY environment variable.
"""

import os
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

import requests

API = "https://megapotato.app/v1"


def error_of(r):
    """(type, message) of an API error, or the raw body if it isn't the usual JSON."""
    try:
        err = r.json()["error"]
        return err["type"], err["message"]
    except (ValueError, KeyError, TypeError):
        return "error", r.text[:200]


def call(method, path, headers=None, **kwargs):
    """One API call.

    Retries what can succeed later (429, 5xx, network errors) and stops on everything else.
    """
    headers = {
        "Authorization": f"Bearer {os.environ['MEGAPOTATO_API_KEY']}",
        **(headers or {}),
    }
    for attempt in range(8):
        try:
            r = requests.request(
                method, f"{API}{path}", headers=headers, timeout=70, **kwargs
            )
        except (requests.ConnectionError, requests.Timeout):
            time.sleep(2**attempt)
            continue
        if r.ok:
            return r.json()
        kind, message = error_of(r)
        # spend_limit_reached is a 429 too, but it resets only at 00:00 UTC:
        # not worth waiting for.
        if r.status_code >= 500 or (
            r.status_code == 429 and kind != "spend_limit_reached"
        ):
            time.sleep(float(r.headers.get("Retry-After", 2**attempt)))
            continue
        sys.exit(f"{r.status_code} {kind}: {message}")
    sys.exit("gave up after repeated temporary errors")


def main():
    if len(sys.argv) < 2 or not os.environ.get("MEGAPOTATO_API_KEY"):
        sys.exit("usage: MEGAPOTATO_API_KEY=... python upscale.py photo.jpg [scale]")
    src = Path(sys.argv[1])
    scale = sys.argv[2] if len(sys.argv) > 2 else "4"

    # Bytes, not an open file: a retried upload must send the whole photo again.
    photo = src.read_bytes()
    # One key per run: if the upload is retried, the server returns the same job
    # and charges once.
    key = f"upscale-{uuid.uuid4()}"
    job = call(
        "POST",
        "/upscale",
        headers={"Idempotency-Key": key},
        files={"file": (src.name, photo)},
        data={"upscale": scale},
    )
    print(f"job {job['id']}: {job['cost_chips']} chips")

    # Each request waits up to 55 s on the server. Read the job at least once, even if
    # the upload answer says "completed": only this request carries result_url and error.
    while True:
        job = call("GET", f"/jobs/{job['id']}", params={"wait": 55})
        if job["status"] in ("completed", "failed"):
            break
        eta = job.get("eta_seconds")
        print(job["status"] + (f", about {eta:.0f} s left" if eta else ""))

    if job["status"] == "failed":
        sys.exit(f"failed: {job['error']}")

    # The link works for about an hour. Results are PNG; test keys return a sample JPEG.
    result = requests.get(job["result_url"], timeout=120)
    result.raise_for_status()
    ext = Path(urlparse(job["result_url"]).path).suffix or ".png"
    out = src.with_name(f"{src.stem}_x{scale}{ext}")
    out.write_bytes(result.content)
    print(f"saved {out}")


if __name__ == "__main__":
    main()
