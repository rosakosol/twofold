#!/usr/bin/env python3
"""
Create (or reuse) two Twofold accounts and pair them into a couple.

The point is to skip onboarding for test setup. Onboarding is ~25 screens ending at a paywall, and
driving it through the UI to reach a *paired* couple is slow and brittle — but almost everything
worth testing in Twofold only exists once two accounts are paired. This does that setup against the
backend directly, so the UI tests can start from a plain email/password sign-in.

Credentials come from the environment, never from this file:

    export TWOFOLD_A_EMAIL=... TWOFOLD_A_PASSWORD=...
    export TWOFOLD_B_EMAIL=... TWOFOLD_B_PASSWORD=...
    python3 scripts/seed-test-couple.py

Safe to re-run: signup falls back to sign-in when the account already exists, and pairing is skipped
when the two are already a couple.

This writes to whatever project SUPABASE_URL points at — production by default. It is for
disposable test accounts only.
"""

import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("SUPABASE_URL", "https://ipfzswswwukfqphloojo.supabase.co")
# The publishable (anon) key — the same one that ships in the client, safe by design: RLS is what
# actually scopes access. See SupabaseConfig.swift.
KEY = os.environ.get(
    "SUPABASE_PUBLISHABLE_KEY", "sb_publishable_KvH6r2_haPL1sbAc1d4F-Q_5l1ImkpK"
)


def call(path, payload=None, token=None, method="POST"):
    headers = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(f"{URL}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read().decode()
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            return {"_error": json.loads(detail)}
        except json.JSONDecodeError:
            return {"_error": {"msg": detail[:200]}}


def account(email, password, label):
    """Sign up, or sign in if the account already exists. Returns (token, user_id)."""
    res = call("/auth/v1/signup", {"email": email, "password": password})
    if res.get("access_token"):
        print(f"  {label}: created")
        return res["access_token"], res["user"]["id"]

    res = call("/auth/v1/token?grant_type=password", {"email": email, "password": password})
    if res.get("access_token"):
        print(f"  {label}: already existed, signed in")
        return res["access_token"], res["user"]["id"]

    err = res.get("_error", res)
    sys.exit(f"  {label}: could not sign up or sign in — {err.get('msg') or err}")


def set_name(token, user_id, name):
    call(
        f"/rest/v1/profiles?id=eq.{user_id}",
        {"first_name": name},
        token=token,
        method="PATCH",
    )


def couple_id_for(token):
    rows = call("/rest/v1/couples?select=id,status&status=eq.active", token=token, method="GET")
    if isinstance(rows, list) and rows:
        return rows[0]["id"]
    return None


def main():
    required = ["TWOFOLD_A_EMAIL", "TWOFOLD_A_PASSWORD", "TWOFOLD_B_EMAIL", "TWOFOLD_B_PASSWORD"]
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        sys.exit("Set these first: " + ", ".join(missing))

    print(f"Project: {URL}")
    print("Accounts:")
    a_token, a_id = account(os.environ["TWOFOLD_A_EMAIL"], os.environ["TWOFOLD_A_PASSWORD"], "A")
    b_token, b_id = account(os.environ["TWOFOLD_B_EMAIL"], os.environ["TWOFOLD_B_PASSWORD"], "B")

    set_name(a_token, a_id, os.environ.get("TWOFOLD_A_NAME", "Alex"))
    set_name(b_token, b_id, os.environ.get("TWOFOLD_B_NAME", "Sam"))

    existing = couple_id_for(a_token)
    if existing:
        print(f"Couple: already paired ({existing})")
        return

    print("Pairing:")
    invite = call("/rest/v1/rpc/create_invite_code", {}, token=a_token)
    if isinstance(invite, dict) and "_error" in invite:
        sys.exit(f"  create_invite_code failed — {invite['_error']}")
    # The RPC returns the whole invite row, not a bare string.
    code = invite["code"] if isinstance(invite, dict) else str(invite)
    print(f"  A's invite code: {code}")

    redeemed = call("/rest/v1/rpc/redeem_invite_code", {"p_code": code}, token=b_token)
    if isinstance(redeemed, dict) and "_error" in redeemed:
        sys.exit(f"  redeem_invite_code failed — {redeemed['_error']}")

    # Redeeming doesn't pair anyone on its own — it raises a request the inviter has to accept,
    # which is the same two-step the app puts a human through.
    # It lands in connection_requests, not couples — a couple row only appears on acceptance.
    pending = call(
        "/rest/v1/connection_requests?select=id,status&status=eq.pending",
        token=a_token,
        method="GET",
    )
    if isinstance(pending, list) and pending:
        request_id = pending[0]["id"]
        print(f"  B redeemed it; A accepting request {request_id}")
        accepted = call(
            "/rest/v1/rpc/respond_to_connection_request",
            {"p_request_id": request_id, "p_accept": True},
            token=a_token,
        )
        if isinstance(accepted, dict) and "_error" in accepted:
            sys.exit(f"  respond_to_connection_request failed — {accepted['_error']}")
    else:
        print("  no pending request found after redeem")

    paired = couple_id_for(a_token)
    print(f"Couple: {'paired — ' + str(paired) if paired else 'redeem returned but no active couple found'}")
    if not paired:
        print("  (redeeming may create a pending request the inviter must accept — check the app)")


if __name__ == "__main__":
    main()
