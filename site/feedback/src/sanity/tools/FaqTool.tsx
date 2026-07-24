"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { faqSupabase, type FaqEntryRow } from "@/sanity/tools/faqSupabaseClient";

// Custom Sanity Studio tool — reads/writes the main Twofold app's `faq_entries` Supabase table
// directly, rather than Sanity's own document store. This table is the single FAQ content
// source for both the marketing site's /faq page and the iOS app's Settings > Support screen
// (see supabase/migrations/20260901001200_faq_entries.sql and 20260901001300's seed content).
// Deliberately plain inline styles rather than @sanity/ui — this project doesn't have that
// package installed, and this tool is simple enough not to need it.
//
// Reads go straight to Supabase with the anon key (faq_entries has a public SELECT policy).
// Writes go through the admin-faq Edge Function instead (see its own doc comment for why: this
// tool has no Supabase user session to authenticate a direct write with).

const FUNCTIONS_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/admin-faq`;
const ADMIN_SECRET = process.env.NEXT_PUBLIC_FAQ_ADMIN_SECRET ?? "";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

interface DraftEntry {
  id: string | null; // null while creating a brand new entry
  category: string;
  question: string;
  answer: string;
  sortOrder: string; // kept as a string while editing so an empty field doesn't fight the input
}

const EMPTY_DRAFT: DraftEntry = { id: null, category: "", question: "", answer: "", sortOrder: "0" };

async function callAdmin(method: "POST" | "PATCH" | "DELETE", id: string | null, body?: unknown) {
  const url = id ? `${FUNCTIONS_URL}?id=${encodeURIComponent(id)}` : FUNCTIONS_URL;
  const res = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      "x-admin-secret": ADMIN_SECRET,
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}) as { error?: string });
    throw new Error(data.error ?? `Request failed (${res.status})`);
  }
  return res.json();
}

export function FaqTool() {
  const [entries, setEntries] = useState<FaqEntryRow[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [draft, setDraft] = useState<DraftEntry | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setIsLoading(true);
    setLoadError(null);
    const { data, error } = await faqSupabase.from("faq_entries").select("*").order("sort_order");
    if (error) setLoadError(error.message);
    else setEntries((data as FaqEntryRow[] | null) ?? []);
    setIsLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const grouped = useMemo(() => {
    const byCategory = new Map<string, FaqEntryRow[]>();
    for (const entry of entries) {
      const key = entry.category ?? "(no category)";
      const list = byCategory.get(key);
      if (list) list.push(entry);
      else byCategory.set(key, [entry]);
    }
    return Array.from(byCategory.entries());
  }, [entries]);

  function startEdit(entry: FaqEntryRow) {
    setSaveError(null);
    setDraft({
      id: entry.id,
      category: entry.category ?? "",
      question: entry.question,
      answer: entry.answer,
      sortOrder: String(entry.sort_order),
    });
  }

  function startNew() {
    setSaveError(null);
    setDraft({ ...EMPTY_DRAFT });
  }

  async function save() {
    if (!draft) return;
    if (!draft.question.trim() || !draft.answer.trim()) {
      setSaveError("Question and answer are both required.");
      return;
    }
    setIsSaving(true);
    setSaveError(null);
    const body = {
      category: draft.category.trim() || null,
      question: draft.question.trim(),
      answer: draft.answer.trim(),
      sortOrder: Number.parseInt(draft.sortOrder, 10) || 0,
    };
    try {
      await callAdmin(draft.id ? "PATCH" : "POST", draft.id, body);
      setDraft(null);
      await load();
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : "Couldn't save that entry.");
    } finally {
      setIsSaving(false);
    }
  }

  async function remove(entry: FaqEntryRow) {
    if (!window.confirm(`Delete "${entry.question}"? This can't be undone.`)) return;
    setIsSaving(true);
    setSaveError(null);
    try {
      await callAdmin("DELETE", entry.id);
      await load();
    } catch (err) {
      setSaveError(err instanceof Error ? err.message : "Couldn't delete that entry.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div style={{ maxWidth: 760, margin: "0 auto", padding: "32px 24px", fontFamily: "inherit" }}>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", marginBottom: 8 }}>
        <h1 style={{ fontSize: 20, fontWeight: 600, margin: 0 }}>FAQ</h1>
        <button type="button" onClick={startNew} style={buttonStyle(true)}>
          + New entry
        </button>
      </div>
      <p style={{ color: "#6b7280", fontSize: 13, marginTop: 0, marginBottom: 24 }}>
        Shared by the marketing site&apos;s /faq page and the iOS app&apos;s Settings &gt; Support screen — changes here
        go live on both within about a minute.
      </p>

      {isLoading && <p>Loading…</p>}
      {loadError && <p style={{ color: "#b91c1c" }}>{loadError}</p>}

      {!isLoading &&
        !loadError &&
        grouped.map(([category, categoryEntries]) => (
          <section key={category} style={{ marginBottom: 28 }}>
            <h2 style={{ fontSize: 13, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.4, color: "#6b7280", marginBottom: 8 }}>
              {category}
            </h2>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {categoryEntries.map((entry) => (
                <div
                  key={entry.id}
                  style={{
                    border: "1px solid #e5e7eb",
                    borderRadius: 8,
                    padding: "12px 14px",
                    display: "flex",
                    alignItems: "flex-start",
                    gap: 12,
                  }}
                >
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 500 }}>{entry.question}</div>
                    <div style={{ color: "#6b7280", fontSize: 13, marginTop: 2 }}>{entry.answer}</div>
                    <div style={{ color: "#9ca3af", fontSize: 12, marginTop: 4 }}>sort order: {entry.sort_order}</div>
                  </div>
                  <div style={{ display: "flex", gap: 6, flexShrink: 0 }}>
                    <button type="button" onClick={() => startEdit(entry)} style={buttonStyle(false)}>
                      Edit
                    </button>
                    <button type="button" onClick={() => remove(entry)} disabled={isSaving} style={buttonStyle(false, true)}>
                      Delete
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </section>
        ))}

      {draft && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0,0,0,0.35)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
          }}
        >
          <div style={{ background: "white", borderRadius: 12, padding: 24, width: 480, maxWidth: "90vw" }}>
            <h3 style={{ marginTop: 0 }}>{draft.id ? "Edit entry" : "New entry"}</h3>

            <label style={labelStyle}>Category</label>
            <input
              value={draft.category}
              onChange={(e) => setDraft({ ...draft, category: e.target.value })}
              placeholder="e.g. Getting started"
              style={inputStyle}
            />

            <label style={labelStyle}>Question</label>
            <input value={draft.question} onChange={(e) => setDraft({ ...draft, question: e.target.value })} style={inputStyle} />

            <label style={labelStyle}>Answer</label>
            <textarea
              value={draft.answer}
              onChange={(e) => setDraft({ ...draft, answer: e.target.value })}
              rows={5}
              style={{ ...inputStyle, resize: "vertical" }}
            />

            <label style={labelStyle}>Sort order (lower shows first)</label>
            <input
              type="number"
              value={draft.sortOrder}
              onChange={(e) => setDraft({ ...draft, sortOrder: e.target.value })}
              style={inputStyle}
            />

            {saveError && <p style={{ color: "#b91c1c", fontSize: 13 }}>{saveError}</p>}

            <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 16 }}>
              <button type="button" onClick={() => setDraft(null)} disabled={isSaving} style={buttonStyle(false)}>
                Cancel
              </button>
              <button type="button" onClick={save} disabled={isSaving} style={buttonStyle(true)}>
                {isSaving ? "Saving…" : "Save"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const labelStyle: React.CSSProperties = { display: "block", fontSize: 12, fontWeight: 500, color: "#374151", marginTop: 12, marginBottom: 4 };
const inputStyle: React.CSSProperties = {
  width: "100%",
  boxSizing: "border-box",
  padding: "8px 10px",
  borderRadius: 6,
  border: "1px solid #d1d5db",
  fontSize: 14,
  fontFamily: "inherit",
};

function buttonStyle(primary: boolean, destructive = false): React.CSSProperties {
  return {
    padding: "6px 12px",
    borderRadius: 6,
    fontSize: 13,
    fontWeight: 500,
    cursor: "pointer",
    border: primary ? "none" : "1px solid #d1d5db",
    background: primary ? (destructive ? "#dc2626" : "#111827") : "white",
    color: primary ? "white" : destructive ? "#b91c1c" : "#111827",
  };
}
