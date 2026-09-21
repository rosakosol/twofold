"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, Loader2, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { nullableArg } from "@/lib/db/nullableArg";

export interface SupportRequest {
  id: string;
  thread_id: string;
  /** Appears in the Reply-To of anything we send, as `support+t<token>@` — which is how their
   * reply comes back identifiable rather than guessed at from its subject. */
  thread_token: string;
  thread_size: number;
  /** 1 is the newest message in the conversation, which is the one that needs answering. */
  thread_position: number;
  thread_last_at: string;
  thread_status: string;
  thread_handler_note: string | null;
  thread_handled_at: string | null;
  profile_id: string | null;
  /** The account this reached, whether or not the sender was signed in. A website submission is
   * matched to an account by the address they typed, at read time — so a request filed before an
   * account existed still resolves once it does. */
  matched_profile_id: string | null;
  email: string | null;
  name: string | null;
  category: string;
  subject: string | null;
  message: string;
  source: string;
  /** Ours or theirs. A thread reads as the conversation it is rather than as one side of it. */
  direction: string;
  created_at: string;
}

/**
 * A queue of conversations, not of messages.
 *
 * Every message used to be its own ticket: somebody writes in, we answer, they say thanks, and
 * that is three things to close. Rows now carry a thread key derived from the subject and sender,
 * and the RPC returns each message with its position and the size of its conversation — so the
 * newest message is the headline and the rest fold underneath it.
 *
 * Status belongs to the conversation too. Closing acts on the whole thread in SQL, and an emailed
 * reply reopens it, which is the case that matters most: a reply to something already closed would
 * otherwise sit behind the default filter, unanswered and unseen.
 */
export function SupportQueue({
  requests,
  activeFilter,
}: {
  requests: SupportRequest[];
  activeFilter: string;
}) {
  // The RPC returns messages already ordered by newest thread, then newest message within it, so
  // grouping in order preserves that without sorting again here.
  const threads: SupportRequest[][] = [];
  const index = new Map<string, number>();
  for (const r of requests) {
    const at = index.get(r.thread_id);
    if (at === undefined) {
      index.set(r.thread_id, threads.length);
      threads.push([r]);
    } else {
      threads[at].push(r);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex gap-1">
        {(["open", "closed", "all"] as const).map((f) => (
          <Link
            key={f}
            href={`/admin/support?status=${f}`}
            className={`rounded-md px-3 py-1.5 text-sm capitalize transition-colors hover:bg-accent ${
              activeFilter === f ? "bg-accent text-foreground" : "text-muted-foreground"
            }`}
          >
            {f}
          </Link>
        ))}
      </div>

      {threads.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            {activeFilter === "open"
              ? "Nothing open. Note that this only holds requests sent since it shipped — anything earlier is in the support inbox only."
              : "Nothing here."}
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-3">
          {threads.map((thread) => (
            <Thread key={thread[0].thread_id} messages={thread} />
          ))}
        </ul>
      )}
    </div>
  );
}

function Thread({ messages }: { messages: SupportRequest[] }) {
  const router = useRouter();
  const latest = messages[0];
  const earlier = messages.slice(1);
  const [note, setNote] = useState(latest.thread_handler_note ?? "");
  const [busy, setBusy] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const isOpen = latest.thread_status === "open";

  async function setStatus(status: "open" | "closed") {
    setBusy(true);
    const supabase = createClient();
    // One row, because status lives on the conversation now rather than being copied onto each of
    // its messages and kept in step by an UPDATE.
    const { error } = await supabase.rpc("admin_set_support_thread_status", {
      p_thread_id: latest.thread_id,
      p_status: status,
      p_note: nullableArg(note || null),
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(status === "closed" ? "Conversation closed." : "Reopened.");
    router.refresh();
  }

  // Abuse reports are the ones with a clock on them — the app promises a response within 48 hours
  // and tells the reporter we never say they got in touch. Marked so they are not skimmed past.
  const urgent = messages.some((m) => m.category === "Report Abuse");

  return (
    <li>
      <Card className={urgent && isOpen ? "border-destructive/50" : undefined}>
        <CardContent className="space-y-3 pt-6">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant={urgent ? "destructive" : "secondary"}>{latest.category}</Badge>
                <Badge variant="outline">{latest.source}</Badge>
                {messages.length > 1 && (
                  <Badge variant="outline">
                    {messages.length} messages
                  </Badge>
                )}
                {!isOpen && <Badge variant="outline">closed</Badge>}
              </div>
              <p className="mt-1.5 text-sm font-medium">{latest.subject || "(no subject)"}</p>
              <p className="text-xs text-muted-foreground">
                {latest.name ? `${latest.name} · ` : ""}
                {latest.email ?? "no address"} · {formatDateTime(latest.created_at)}
              </p>
            </div>

            {latest.matched_profile_id ? (
              <Link
                href={`/admin/users/${latest.matched_profile_id}`}
                className="shrink-0 text-sm underline underline-offset-4"
              >
                Open account
              </Link>
            ) : (
              // Worth saying rather than leaving blank: it usually means they wrote in from an
              // address they never signed up with, which is itself the answer to "why can't they
              // sign in".
              <span className="shrink-0 text-xs text-muted-foreground">No matching account</span>
            )}
          </div>

          <p
            className={`whitespace-pre-wrap rounded-md p-3 text-sm ${
              latest.direction === "outbound" ? "border border-dashed bg-transparent" : "bg-muted/50"
            }`}
          >
            {latest.direction === "outbound" && (
              <span className="mb-1 block text-xs font-medium text-muted-foreground">Your reply</span>
            )}
            {latest.message}
          </p>

          {earlier.length > 0 && (
            <div className="space-y-2">
              <button
                type="button"
                onClick={() => setExpanded((v) => !v)}
                className="text-xs text-muted-foreground underline underline-offset-4 hover:text-foreground"
              >
                {expanded
                  ? "Hide earlier messages"
                  : `Show ${earlier.length} earlier message${earlier.length === 1 ? "" : "s"}`}
              </button>
              {expanded &&
                earlier.map((m) => (
                  <div key={m.id} className="border-l-2 pl-3">
                    <p className="text-xs text-muted-foreground">
                      {m.direction === "outbound" ? "Your reply · " : ""}
                      {formatDateTime(m.created_at)} · {m.source}
                    </p>
                    <p className="mt-1 whitespace-pre-wrap text-sm text-muted-foreground">
                      {m.message}
                    </p>
                  </div>
                ))}
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2">
            <Input
              className="max-w-xs"
              placeholder="What was done about it"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={busy}
              aria-label="Note about how this was handled"
            />
            {isOpen ? (
              <Button variant="outline" size="sm" disabled={busy} onClick={() => setStatus("closed")}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Close
              </Button>
            ) : (
              <Button variant="ghost" size="sm" disabled={busy} onClick={() => setStatus("open")}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <RotateCcw className="h-4 w-4" />}
                Reopen
              </Button>
            )}
            {latest.thread_handled_at && (
              <span className="text-xs text-muted-foreground">
                closed {formatDateTime(latest.thread_handled_at)}
              </span>
            )}
          </div>
        </CardContent>
      </Card>
    </li>
  );
}

function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}
