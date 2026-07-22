#!/usr/bin/env python3
"""
Batch-tests the parse-flight-email edge function against a folder of .eml and
standalone .pdf files.

For .eml files, mirrors what the iOS Share Extension captures: the email subject,
the body text (prefer text/plain, else strip tags from text/html), and -- only used
server-side as a fallback when subject/body don't yield a flight -- text extracted
from any PDF attachment (boarding pass, e-ticket). Standalone .pdf files (not
attached to an .eml) are sent as pdfText only, with no subject/body, to exercise
the PDF-only fallback path on its own.

Requires the `pdftotext` CLI (poppler) on PATH to test any PDF content -- either
attached or standalone; `brew install poppler` if it's missing. Without it, PDFs
are skipped entirely.

Usage:
  python3 test-batch.py [directory] [--url URL] [--api-key KEY]

Defaults to the local dev stack (`supabase start` / `supabase functions serve`
must be running) and the publishable key already checked into index.ts.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from email import policy
from email.parser import BytesParser
from pathlib import Path

LOCAL_URL = "http://127.0.0.1:54321/functions/v1/parse-flight-email"
LOCAL_PUBLISHABLE_KEY = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

TAG_RE = re.compile(r"<[^>]+>")
WHITESPACE_RE = re.compile(r"[ \t]+")
BLANK_LINES_RE = re.compile(r"\n{3,}")

PDFTOTEXT = shutil.which("pdftotext")


def strip_html(raw_html: str) -> str:
    text = re.sub(r"(?is)<(script|style).*?</\1>", "", raw_html)
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</p>", "\n\n", text)
    text = TAG_RE.sub("", text)
    text = html.unescape(text)
    text = WHITESPACE_RE.sub(" ", text)
    text = BLANK_LINES_RE.sub("\n\n", text)
    return text.strip()


def extract_subject(msg) -> str | None:
    subject = msg.get("Subject")
    return subject.strip() if subject and subject.strip() else None


def extract_body(msg) -> str | None:
    plain_part = msg.get_body(preferencelist=("plain",))
    if plain_part is not None:
        content = plain_part.get_content().strip()
        if content:
            return content

    html_part = msg.get_body(preferencelist=("html",))
    if html_part is not None:
        stripped = strip_html(html_part.get_content())
        if stripped:
            return stripped

    return None


def pdf_bytes_to_text(data: bytes) -> str | None:
    if PDFTOTEXT is None or not data:
        return None

    with tempfile.NamedTemporaryFile(suffix=".pdf") as tmp:
        tmp.write(data)
        tmp.flush()
        result = subprocess.run(
            [PDFTOTEXT, "-layout", tmp.name, "-"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        text = result.stdout.strip()
        return text or None


def extract_pdf_text(msg) -> str | None:
    if PDFTOTEXT is None:
        return None

    for part in msg.walk():
        filename = part.get_filename()
        is_pdf = part.get_content_type() == "application/pdf" or (filename and filename.lower().endswith(".pdf"))
        if not is_pdf:
            continue

        try:
            data = part.get_content()
        except Exception:
            continue
        if not isinstance(data, bytes):
            continue

        text = pdf_bytes_to_text(data)
        if text:
            return text

    return None


def call_edge_function(url: str, api_key: str, subject: str | None, body: str | None, pdf_text: str | None) -> dict:
    payload = {}
    if subject:
        payload["subject"] = subject
    if body:
        payload["body"] = body
    if pdf_text:
        payload["pdfText"] = pdf_text

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apiKey": api_key,
            "Authorization": f"Bearer {api_key}",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", nargs="?", default="itineraries", help="Folder of .eml/.pdf files")
    parser.add_argument("--url", default=LOCAL_URL, help="Edge function URL")
    parser.add_argument("--api-key", default=LOCAL_PUBLISHABLE_KEY, help="Supabase publishable/anon key")
    args = parser.parse_args()

    if PDFTOTEXT is None:
        print("note: `pdftotext` not found on PATH -- all PDF content will be skipped\n", file=sys.stderr)

    directory = Path(args.directory)
    eml_files = sorted(directory.glob("*.eml"))
    pdf_files = sorted(directory.glob("*.pdf"))
    if not eml_files and not pdf_files:
        print(f"No .eml or .pdf files found in {directory}", file=sys.stderr)
        return 1

    def run(name: str, subject: str | None, body: str | None, pdf_text: str | None) -> None:
        print(f"\n=== {name} ===")
        print(f"  subject: {subject!r}")
        print(f"  body: {'present, %d chars' % len(body) if body else None}")
        print(f"  pdfText: {'present, %d chars' % len(pdf_text) if pdf_text else None}")

        if not subject and not body and not pdf_text:
            print("  (nothing extracted -- would fall back to 'Add manually' in-app)")
            return

        try:
            result = call_edge_function(args.url, args.api_key, subject, body, pdf_text)
        except urllib.error.HTTPError as e:
            print(f"  HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}")
            return
        except urllib.error.URLError as e:
            print(f"  Request failed: {e.reason}")
            print("  (is `supabase start` / `supabase functions serve` running?)")
            return

        print("  result:", json.dumps(result, indent=2))

    for eml_path in eml_files:
        with open(eml_path, "rb") as f:
            msg = BytesParser(policy=policy.default).parse(f)
        run(eml_path.name, extract_subject(msg), extract_body(msg), extract_pdf_text(msg))

    for pdf_path in pdf_files:
        pdf_text = pdf_bytes_to_text(pdf_path.read_bytes())
        run(f"{pdf_path.name} (standalone PDF)", None, None, pdf_text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
