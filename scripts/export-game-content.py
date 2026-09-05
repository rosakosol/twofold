#!/usr/bin/env python3
"""
Export every game deck and its content into the JSON the app ships as its offline seed.

Games are the one part of Twofold that was entirely unavailable without a connection: the deck
list, the round content and the session that ties them together all came from the backend, so a
cold launch on a plane reached a Games hub with nothing in it. The app now carries a copy of the
content, and this is what produces it.

The output is a build input, not a runtime cache. It's committed and re-exported whenever content
changes; the app refreshes from the backend whenever it's online, so this only has to be good
enough for someone who has never had a connection since installing.

PREMIUM CONTENT IS DELIBERATELY EXCLUDED. An .ipa is a zip and this file is plain JSON, so
everything exported here is readable by anyone who downloads the app, subscriber or not. Seeding
the premium catalogue would have put 131 of 191 decks and 1,468 of 1,987 questions — most of what
the subscription sells — in the hands of people who never paid for it. Premium subscribers still
get their decks offline: the in-app refresh (`BackendService.fetchGameContentPayload`) pulls the
full catalogue for their tier and caches it, so the only gap is a premium user who has never once
had a connection since installing, which is also a user who has never been able to subscribe.

Credentials come from the environment, never from this file — any authenticated account can read
the content tables (see `discussion_topics_select_authenticated` and its siblings), so a disposable
test account is the right thing to use:

    export TWOFOLD_A_EMAIL=... TWOFOLD_A_PASSWORD=...
    python3 scripts/export-game-content.py

Writes Twofold/Twofold/Resources/GameContentSeed.json.
"""

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
OUTPUT = os.path.join(
    REPO_ROOT, "Twofold", "Twofold", "Resources", "GameContentSeed.json"
)

# Which table holds the rounds for each game type, and which columns the app actually needs. Kept
# narrow deliberately: this file ships inside the app, so anything exported here is anything a
# user could read out of the bundle.
# Only this tier is seeded into the bundle — see the note above. `game_decks.tier` and each content
# row's own `tier` are both checked: a plus deck is not assumed to contain only plus rows.
SEED_TIERS = {"plus"}

CONTENT_TABLES = {
    "trivia_battle": (
        "trivia_questions",
        "id,deck_id,question,options,correct_answer,explanation,difficulty,category,tier,active",
    ),
    "more_likely": ("more_likely_prompts", "id,deck_id,prompt,category,tier,active"),
    "this_or_that": (
        "this_or_that_prompts",
        "id,deck_id,option_a,option_b,category,tier,active",
    ),
    "deep_conversations": (
        "deep_conversation_topics",
        "id,deck_id,topic,category,tier,active",
    ),
}


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
        fail("set TWOFOLD_A_EMAIL and TWOFOLD_A_PASSWORD (see this file's docstring)")
    result = request(
        "/auth/v1/token",
        params={"grant_type": "password"},
        method="POST",
        body={"email": email, "password": password},
    )
    return result["access_token"]


def fetch_all(table, columns, token):
    """Pages explicitly — PostgREST caps a plain select at 1000 rows and returns no warning when
    it truncates, which would silently ship a partial deck."""
    rows = []
    page = 1000
    while True:
        offset = len(rows)
        batch = request(
            f"/rest/v1/{table}",
            token=token,
            params={
                "select": columns,
                "order": "id.asc",
                "limit": page,
                "offset": offset,
            },
        )
        rows.extend(batch)
        if len(batch) < page:
            return rows


def main():
    token = sign_in()

    decks = fetch_all(
        "game_decks", "id,topic,game_type,title,emoji,tier,sort_order,active", token
    )
    # Inactive rows are excluded here rather than at runtime, matching `fetchGameDecks`'s
    # `.eq("active", true)` and `start_deck_session`'s own `and active` — the app must not be able
    # to build a deck offline that the backend would refuse to build online.
    decks = [
        d for d in decks
        if d.get("active") and d.get("game_type") in CONTENT_TABLES and d.get("tier") in SEED_TIERS
    ]
    seeded_deck_ids = {d["id"] for d in decks}
    decks.sort(key=lambda d: (d.get("sort_order") or 0, d["id"]))

    content = {}
    for game_type, (table, columns) in CONTENT_TABLES.items():
        rows = [
            r for r in fetch_all(table, columns, token)
            if r.get("active")
            and r.get("deck_id") in seeded_deck_ids
            and r.get("tier") in SEED_TIERS
        ]
        for row in rows:
            row.pop("active", None)
        content[game_type] = rows

    # `question_count` is what the deck list shows before anything is opened, and the app computes
    # a deck's rounds from this same content, so deriving it here keeps the two from disagreeing.
    by_deck = {}
    for game_type, rows in content.items():
        for row in rows:
            by_deck.setdefault(row["deck_id"], []).append(row)
    for deck in decks:
        deck["question_count"] = len(by_deck.get(deck["id"], []))
        deck.pop("active", None)

    # A seeded deck with no rows left after filtering would open to nothing offline, so it is
    # dropped rather than shipped broken.
    empty = [d for d in decks if d["question_count"] == 0]
    if empty:
        print(f"dropping {len(empty)} deck(s) left with no seedable content: "
              f"{', '.join(d['title'] for d in empty[:5])}")
        decks = [d for d in decks if d["question_count"] > 0]

    seed = {"version": 1, "decks": decks, "content": content}
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as handle:
        json.dump(seed, handle, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

    total = sum(len(rows) for rows in content.values())
    size = os.path.getsize(OUTPUT)
    print(f"{len(decks)} decks, {total} content rows -> {OUTPUT} ({size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
