"use client";

import { useState } from "react";
import { toast } from "sonner";
import { createClient } from "@/lib/supabase/client";

type List = "product_news" | "feedback_updates" | "android_waitlist";

export interface EmailPreferences {
  product_news: boolean;
  feedback_updates: boolean;
  android_waitlist: boolean;
}

const LISTS: { key: List; label: string; hint: string }[] = [
  { key: "product_news", label: "Product news", hint: "New features, launches and the occasional offer. Off unless you turn it on." },
  { key: "feedback_updates", label: "Feedback updates", hint: "A confirmation when you post on the feedback board, and news about your requests." },
  { key: "android_waitlist", label: "Android waitlist", hint: "One email when Twofold for Android ships." },
];

/**
 * Which emails this account gets (supabase/migrations/20261112000000). The same three lists every
 * email's unsubscribe link changes, so turning one off here or from an email is the same thing.
 * Account, security, billing and support mail is not optional and is not listed.
 */
export function EmailPreferencesCard({ initial }: { initial: EmailPreferences | null }) {
  const [prefs, setPrefs] = useState<EmailPreferences | null>(initial);
  const [busy, setBusy] = useState<List | null>(null);

  async function set(list: List, enabled: boolean) {
    if (!prefs) return;
    setBusy(list);
    setPrefs({ ...prefs, [list]: enabled });
    const { error } = await createClient().rpc("set_my_email_preference", { p_list: list, p_enabled: enabled });
    setBusy(null);
    if (error) {
      setPrefs((p) => (p ? { ...p, [list]: !enabled } : p));
      toast.error("We couldn't save that. Please try again.");
    }
  }

  return (
    <section className="account-card" id="email" aria-labelledby="email-title">
      <div className="account-card-head">
        <h2 id="email-title">Email preferences</h2>
      </div>
      {prefs ? (
        <fieldset className="account-prefs">
          <legend className="sr-only">Emails you get from us</legend>
          {LISTS.map((list) => (
            <label key={list.key} className="account-pref">
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
      ) : (
        <p className="account-muted">Your email preferences couldn&apos;t be loaded just now. Please refresh to try again.</p>
      )}
      <p className="account-fine">
        Emails about your account, security, billing and support conversations aren&apos;t marketing, so they always
        reach you.
      </p>
    </section>
  );
}
