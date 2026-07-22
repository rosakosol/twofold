#!/usr/bin/env python3
"""
Batch-tests the parse-flight-email edge function against a folder of .eml files.

Mirrors what the iOS Share Extension captures: the email subject, the body text
(prefer text/plain, else strip tags from text/html), and -- only used server-side
as a fallback when subject/body don't yield a flight -- text extracted from any
PDF attachment (boarding pass, e-ticket).

Requires the `pdftotext` CLI (poppler) on PATH to test the PDF fallback path;
`brew install poppler` if it's missing. Without it, PDF attachments are skipped
and only the subject/body path is tested.

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
        if not isinstance(data, bytes) or not data:
            continue

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
    parser.add_argument("directory", nargs="?", default="itineraries", help="Folder of .eml files")
    parser.add_argument("--url", default=LOCAL_URL, help="Edge function URL")
    parser.add_argument("--api-key", default=LOCAL_PUBLISHABLE_KEY, help="Supabase publishable/anon key")
    args = parser.parse_args()

    if PDFTOTEXT is None:
        print("note: `pdftotext` not found on PATH -- PDF-attachment fallback will be skipped for all files\n", file=sys.stderr)

    directory = Path(args.directory)
    eml_files = sorted(directory.glob("*.eml"))
    if not eml_files:
        print(f"No .eml files found in {directory}", file=sys.stderr)
        return 1

    for eml_path in eml_files:
        print(f"\n=== {eml_path.name} ===")
        with open(eml_path, "rb") as f:
            msg = BytesParser(policy=policy.default).parse(f)

        subject = extract_subject(msg)
        body = extract_body(msg)
        pdf_text = extract_pdf_text(msg)

        print(f"  subject: {subject!r}")
        print(f"  body: {'present, %d chars' % len(body) if body else None}")
        print(f"  pdfText: {'present, %d chars' % len(pdf_text) if pdf_text else None}")

        if not subject and not body and not pdf_text:
            print("  (nothing extracted -- would fall back to 'Add manually' in-app)")
            continue

        try:
            result = call_edge_function(args.url, args.api_key, subject, body, pdf_text)
        except urllib.error.HTTPError as e:
            print(f"  HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}")
            continue
        except urllib.error.URLError as e:
            print(f"  Request failed: {e.reason}")
            print("  (is `supabase start` / `supabase functions serve` running?)")
            continue

        print("  result:", json.dumps(result, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
