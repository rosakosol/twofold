"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { CheckCircle2, Loader2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

type List = "product_news" | "feedback_updates" | "android_waitlist";

const LISTS: { key: List; label: string; hint: string }[] = [
  { key: "product_news", label: "Product news", hint: "New features, launches and the occasional offer." },
  { key: "feedback_updates", label: "Feedback updates", hint: "Confirmations and news about requests you post." },
  { key: "android_waitlist", label: "Android waitlist", hint: "One email when Twofold for Android ships." },
];

type Prefs = { masked_email: string; product_news: boolean; feedback_updates: boolean; android_waitlist: boolean };

export function UnsubscribeClient() {
  const params = useSearchParams();
  const token = params.get("token") ?? "";
  const requested = (params.get("list") ?? "") as List;
  const [prefs, setPrefs] = useState<Prefs | null | undefined>(undefined);
  const [busy, setBusy] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // A malformed token is known to be invalid without asking anyone.
  const wellFormed = /^[0-9a-f-]{36}$/i.test(token);

  useEffect(() => {
    if (!wellFormed) return;
    createClient()
      .rpc("email_preferences_by_token", { p_token: token })
      .then(({ data }) => setPrefs(Array.isArray(data) && data[0] ? (data[0] as Prefs) : null));
  }, [token, wellFormed]);

  async function set(list: List | "all", enabled: boolean) {
    setBusy(list);
    setError(null);
    const { data, error: rpcError } = await createClient().rpc("set_email_preference_by_token", {
      p_token: token,
      p_list: list,
      p_enabled: enabled,
    });
    setBusy(null);
    if (rpcError || data === false) {
      setError("That didn't work. Please try again, or email support@twofoldapp.com.au.");
      return;
    }
    setPrefs((p) =>
      p
        ? list === "all"
          ? { ...p, product_news: false, feedback_updates: false, android_waitlist: false }
          : { ...p, [list]: enabled }
        : p,
    );
    if (!enabled) setDone(list === "all" ? "You won't get any of these emails from us." : `You're unsubscribed from ${LISTS.find((l) => l.key === list)?.label.toLowerCase()}.`);
  }

  if (prefs === undefined && wellFormed) {
    return (
      <div className="unsub-card" aria-busy="true">
        <Loader2 className="unsub-spin" aria-hidden />
        <p className="sr-only">Loading your email preferences</p>
      </div>
    );
  }

  if (!prefs) {
    return (
      <div className="unsub-card">
        <h1 id="unsub-title">This link isn&apos;t valid</h1>
        <p>
          It may have been copied incompletely. You can manage your emails from your{" "}
          <Link className="btn-link" href="/account#email">
            account
          </Link>
          , or email <a className="btn-link" href="mailto:support@twofoldapp.com.au">support@twofoldapp.com.au</a>.
        </p>
      </div>
    );
  }

  const target = LISTS.find((l) => l.key === requested);

  return (
    <div className="unsub-card">
      <h1 id="unsub-title">Email preferences</h1>
      <p className="unsub-who">For {prefs.masked_email}</p>

      {done ? (
        <p className="unsub-done" role="status">
          <CheckCircle2 aria-hidden />
          {done}
        </p>
      ) : (
        target &&
        prefs[target.key] && (
          <div className="unsub-ask">
            <p>
              Unsubscribe from <strong>{target.label.toLowerCase()}</strong>? {target.hint}
            </p>
            <button type="button" className="btn btn-primary" disabled={busy !== null} onClick={() => set(target.key, false)}>
              {busy === target.key && <Loader2 className="unsub-spin" aria-hidden />}
              Unsubscribe
            </button>
          </div>
        )
      )}

      <fieldset className="unsub-lists">
        <legend>Emails you get from us</legend>
        {LISTS.map((list) => (
          <label key={list.key} className="unsub-row">
            <span>
              <strong>{list.label}</strong>
              <span>{list.hint}</span>
            </span>
            <input
              type="checkbox"
              role="switch"
              className="pref-switch"
              checked={prefs[list.key]}
              disabled={busy !== null}
              onChange={(event) => set(list.key, event.target.checked)}
            />
          </label>
        ))}
      </fieldset>

      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}

      <p className="unsub-note">
        Emails about your account, security, billing and support conversations aren&apos;t marketing, so they always
        reach you. Signed in? Your{" "}
        <Link className="btn-link" href="/account#email">
          account page
        </Link>{" "}
        has the same settings.
      </p>
      {(prefs.product_news || prefs.feedback_updates || prefs.android_waitlist) && (
        <button type="button" className="btn-link link-button" disabled={busy !== null} onClick={() => set("all", false)}>
          Unsubscribe from all of these
        </button>
      )}
    </div>
  );
}
