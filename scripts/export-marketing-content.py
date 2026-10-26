#!/usr/bin/env python3
"""
Export the game catalogue (decks and their questions) for marketing: TikTok quiz and carousel
slides built from the real in-app content.

Not the app's offline seed. That is scripts/export-game-content.py, which writes Plus content
only into the app bundle. This writes a readable copy for people, outside the app, in two shapes:

    exports/game-content/game-content.json   decks, each with its questions nested
    exports/game-content/game-content.csv    one row per question, for a spreadsheet or importer

Every question has a `prompt` (the line to put on a slide) whatever the game, plus the game's own
fields: trivia keeps its options, answer and explanation; This or That keeps both options.

Two sources:

  Live (default): signs in and reads the content tables as that account, so the account decides
  what comes back. Use a Premium account for the whole catalogue; a Plus account only sees Plus
  questions, and nobody sees the After Dark decks without the adult opt-in.

      $env:TWOFOLD_A_EMAIL = "..."; $env:TWOFOLD_A_PASSWORD = "..."
      python3 scripts/export-marketing-content.py

  Seed (--from-seed): reads Twofold/Twofold/Resources/GameContentSeed.json. No login, Plus only.

      python3 scripts/export-marketing-content.py --from-seed

After Dark (adult) decks are left out unless --include-adult is passed: they are not for an
all-ages feed. Inactive decks and questions are always left out.

Writes to exports/ at the repo root, which is gitignored.
"""

import argparse
import csv
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ipfzswswwukfqphloojo.supabase.co")
ANON_KEY = os.environ.get(
    "SUPABASE_ANON_KEY", "sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK"
)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(REPO_ROOT, "Twofold", "Twofold", "Resources", "GameContentSeed.json")
DEFAULT_OUT = os.path.join(REPO_ROOT, "exports", "game-content")

# Game type -> (content table, columns, the name the app shows for the game).
GAMES = {
    "trivia_battle": (
        "trivia_questions",
        "id,deck_id,question,options,correct_answer,explanation,difficulty,category,tier,active",
        "Trivia Battle",
    ),
    "more_likely": (
        "more_likely_prompts",
        "id,deck_id,prompt,category,tier,active",
        "Who's More Likely To",
    ),
    "this_or_that": (
        "this_or_that_prompts",
        "id,deck_id,option_a,option_b,category,tier,active",
        "This or That",
    ),
    "deep_conversations": (
        "deep_conversation_topics",
        "id,deck_id,topic,category,tier,active",
        "Deep Conversation",
    ),
}

CSV_COLUMNS = [
    "deck_title", "deck_emoji", "topic", "game", "tier",
    "prompt", "option_a", "option_b", "options", "correct_answer", "explanation", "difficulty",
]


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def request(path, token=None, params=None, method="GET", body=None):
    url = f"{SUPABASE_URL}{path}"
    if params:
        url += "?" + "&".join(f"{k}={v}" for k, v in params.items())
    headers = {"apikey": ANON_KEY, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        fail(f"{method} {path} -> {error.code} {error.read().decode()[:300]}")


def sign_in():
    email = os.environ.get("TWOFOLD_A_EMAIL")
    password = os.environ.get("TWOFOLD_A_PASSWORD")
    if not email or not password:
        fail("set TWOFOLD_A_EMAIL and TWOFOLD_A_PASSWORD, or pass --from-seed (see this file's docstring)")
    result = request(
        "/auth/v1/token",
        params={"grant_type": "password"},
        method="POST",
        body={"email": email, "password": password},
    )
    return result["access_token"]


def fetch_all(table, columns, token):
    """Pages explicitly: PostgREST caps a plain select at 1000 rows without saying so."""
    rows = []
    page = 1000
    while True:
        batch = request(
            f"/rest/v1/{table}",
            token=token,
            params={"select": columns, "order": "id.asc", "limit": page, "offset": len(rows)},
        )
        rows.extend(batch)
        if len(batch) < page:
            return rows


def load_live():
    token = sign_in()
    decks = fetch_all("game_decks", "id,topic,game_type,title,emoji,tier,sort_order,active,adult", token)
    content = {game: fetch_all(table, columns, token) for game, (table, columns, _) in GAMES.items()}
    return decks, content, "live"


def load_seed():
    with open(SEED, encoding="utf-8") as handle:
        seed = json.load(handle)
    # The seed holds only active, non-adult Plus content already.
    decks = [dict(d, active=True, adult=False) for d in seed["decks"]]
    content = {game: [dict(r, active=True) for r in rows] for game, rows in seed["content"].items()}
    return decks, content, "seed (Plus only)"


def to_question(game, row):
    """One question in a shape a slide can use: `prompt` is always the line to show."""
    q = {
        "prompt": None,
        "option_a": None,
        "option_b": None,
        "options": None,
        "correct_answer": None,
        "explanation": None,
        "difficulty": None,
        "tier": row.get("tier"),
    }
    if game == "trivia_battle":
        q.update(
            prompt=row.get("question"),
            options=row.get("options"),
            correct_answer=row.get("correct_answer"),
            explanation=row.get("explanation"),
            difficulty=row.get("difficulty"),
        )
    elif game == "more_likely":
        q["prompt"] = row.get("prompt")
    elif game == "this_or_that":
        a, b = row.get("option_a"), row.get("option_b")
        q.update(prompt=f"{a} or {b}?", option_a=a, option_b=b)
    elif game == "deep_conversations":
        q["prompt"] = row.get("topic")
    return q


def main():
    parser = argparse.ArgumentParser(description="Export the game catalogue for marketing.")
    parser.add_argument("--from-seed", action="store_true", help="read the app's offline seed (Plus only) instead of signing in")
    parser.add_argument("--include-adult", action="store_true", help="include the After Dark (18+) decks")
    parser.add_argument("--out", default=DEFAULT_OUT, help=f"output folder (default {DEFAULT_OUT})")
    args = parser.parse_args()

    decks, content, source = load_seed() if args.from_seed else load_live()

    decks = [
        d for d in decks
        if d.get("active") and d.get("game_type") in GAMES and (args.include_adult or not d.get("adult"))
    ]
    by_deck = {}
    for game, rows in content.items():
        for row in rows:
            if row.get("active") and row.get("deck_id"):
                by_deck.setdefault(row["deck_id"], []).append(to_question(game, row))

    out_decks = []
    for d in sorted(decks, key=lambda d: (d.get("topic") or "", d.get("sort_order") or 0, d.get("title") or "")):
        questions = by_deck.get(d["id"], [])
        if not questions:
            continue  # a deck this account can't read any question of, or an empty one
        out_decks.append({
            "title": d.get("title"),
            "emoji": d.get("emoji"),
            "topic": d.get("topic"),
            "game": GAMES[d["game_type"]][2],
            "game_type": d["game_type"],
            "tier": d.get("tier"),
            "adult": bool(d.get("adult")),
            "question_count": len(questions),
            "questions": questions,
        })

    os.makedirs(args.out, exist_ok=True)
    exported_at = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    json_path = os.path.join(args.out, "game-content.json")
    csv_path = os.path.join(args.out, "game-content.csv")

    with open(json_path, "w", encoding="utf-8") as handle:
        json.dump(
            {"exported_at": exported_at, "source": source, "decks": out_decks},
            handle, ensure_ascii=False, indent=2,
        )

    # utf-8-sig so Excel opens the emoji and accents correctly.
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for deck in out_decks:
            for q in deck["questions"]:
                writer.writerow({
                    "deck_title": deck["title"],
                    "deck_emoji": deck["emoji"],
                    "topic": deck["topic"],
                    "game": deck["game"],
                    "tier": q["tier"] or deck["tier"],
                    "prompt": q["prompt"],
                    "option_a": q["option_a"],
                    "option_b": q["option_b"],
                    "options": " | ".join(q["options"]) if q["options"] else None,
                    "correct_answer": q["correct_answer"],
                    "explanation": q["explanation"],
                    "difficulty": q["difficulty"],
                })

    total = sum(d["question_count"] for d in out_decks)
    tiers = {}
    for d in out_decks:
        tiers[d["tier"]] = tiers.get(d["tier"], 0) + 1
    print(f"{len(out_decks)} decks ({', '.join(f'{n} {t}' for t, n in sorted(tiers.items()))}), "
          f"{total} questions, from {source}")
    print(f"  {json_path}\n  {csv_path}")
    if source == "live" and "premium" not in tiers:
        print("note: no Premium decks came back. Sign in as a Premium account for the full catalogue.")


if __name__ == "__main__":
    main()
