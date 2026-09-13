#!/usr/bin/env python
"""Step 1 — download the English Wiktionary JSONL from kaikki.org into data/wiktionary-en.jsonl.

Two sources:
  english  (default) the English-only file, ~3.2 GB uncompressed, direct. kaikki marks it
           deprecated, so it may disappear.
  raw      the all-languages raw-wiktextract-data.jsonl.gz (~2.8 GB compressed, ~23 GB
           uncompressed); streamed through gunzip and filtered to lang_code == "en".

Both are resumable. Usage:  python 01_download.py [--source english|raw] [--force]
"""

from __future__ import annotations

import argparse
import gzip
import shutil
import sys
import urllib.request
from pathlib import Path

from arth_pipeline.config import DATA_DIR
from arth_pipeline.wiktionary import WIKTIONARY_PATH

SOURCES = {
    "english": "https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl",
    "raw": "https://kaikki.org/dictionary/raw-wiktextract-data.jsonl.gz",
}
CHUNK = 1 << 20


def download_resumable(url: str, dest: Path) -> None:
    part = dest.with_suffix(dest.suffix + ".part")
    have = part.stat().st_size if part.exists() else 0
    req = urllib.request.Request(url, headers={"Range": f"bytes={have}-"} if have else {})
    with urllib.request.urlopen(req) as resp:  # noqa: S310 - fixed https URLs
        status = resp.status
        if have and status != 206:
            print("server ignored Range; restarting from zero", file=sys.stderr)
            have = 0
        total = have + int(resp.headers.get("Content-Length") or 0)
        mode = "ab" if have else "wb"
        done = have
        with part.open(mode) as out:
            while True:
                chunk = resp.read(CHUNK)
                if not chunk:
                    break
                out.write(chunk)
                done += len(chunk)
                if done % (64 << 20) < CHUNK:
                    pct = f"{100 * done / total:5.1f}%" if total else ""
                    print(f"\r  {done / (1 << 30):6.2f} GB {pct}", end="", file=sys.stderr)
    print(file=sys.stderr)
    part.replace(dest)


def filter_raw_gz(src: Path, dest: Path) -> None:
    """Stream-decompress and keep English lines. Substring check first; JSON parse is the slow part."""
    kept = 0
    with gzip.open(src, "rb") as f, dest.open("wb") as out:
        for i, line in enumerate(f):
            if b'"lang_code": "en"' in line:
                out.write(line)
                kept += 1
            if i % 1_000_000 == 0:
                print(f"\r  scanned {i:,} kept {kept:,}", end="", file=sys.stderr)
    print(file=sys.stderr)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", choices=SOURCES, default="english")
    ap.add_argument("--force", action="store_true", help="re-download even if the file exists")
    args = ap.parse_args()

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if WIKTIONARY_PATH.exists() and not args.force:
        print(f"{WIKTIONARY_PATH} exists ({WIKTIONARY_PATH.stat().st_size / (1 << 30):.2f} GB); use --force")
        return

    if args.source == "english":
        download_resumable(SOURCES["english"], WIKTIONARY_PATH)
    else:
        gz = DATA_DIR / "raw-wiktextract-data.jsonl.gz"
        download_resumable(SOURCES["raw"], gz)
        tmp = WIKTIONARY_PATH.with_suffix(".filtering")
        filter_raw_gz(gz, tmp)
        shutil.move(tmp, WIKTIONARY_PATH)
    print(f"wrote {WIKTIONARY_PATH} ({WIKTIONARY_PATH.stat().st_size / (1 << 30):.2f} GB)")


if __name__ == "__main__":
    main()
