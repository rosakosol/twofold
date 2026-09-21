"use client";

import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  ChevronLeft,
  Download,
  Inbox,
  Loader2,
  Paperclip,
  Search,
  Send,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";
import { nullableArg } from "@/lib/db/nullableArg";
import { functionErrorMessage } from "@/lib/supabase/functionError";
import { cn } from "@/lib/utils";

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

type Thread = SupportRequest[];

const FILTERS = ["open", "closed", "all"] as const;

/**
 * The support inbox: a list of conversations beside the one being read.
 *
 * It was a stack of cards, each carrying its whole transcript and its own composer. That shape
 * does not survive contact with a real mailbox — every conversation is expanded at once, the
 * screen is mostly other people's problems, and finding the one you were told about means
 * scrolling past the ones you weren't. Mail clients settled on list-beside-conversation decades
 * ago for the reason that still applies: one thing is being answered at a time, and everything
 * else only needs to be findable.
 *
 * Grouping is unchanged — the RPC returns messages ordered by newest conversation, then newest
 * message within it, so a single pass in order produces the threads without sorting again.
 *
 * Status belongs to the conversation rather than to its messages, and an emailed reply reopens it.
 * That last case is the one that matters most: a reply to something already closed would
 * otherwise sit behind the default filter, unanswered and unseen.
 */
export function SupportQueue({
  requests,
  activeFilter,
  initialThreadId,
}: {
  requests: SupportRequest[];
  activeFilter: string;
  initialThreadId?: string;
}) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(initialThreadId ?? null);

  /**
   * The conversation whose status was just changed, kept on screen after the server stops
   * returning it.
   *
   * Closing something from the Open filter — or reopening from Closed — moves it out of the list
   * being looked at, so the next load simply omits it. On screen that is indistinguishable from
   * the button having done nothing: the row disappears and the panel empties. So the last known
   * copy is held here with its new status patched in, and merged back into the list until
   * something else is selected. The operator sees the state change they asked for, on the
   * conversation they asked it of.
   */
  const [pinned, setPinned] = useState<Thread | null>(null);

  // Switching filters is a navigation within the same route, so this component is not remounted
  // and a pinned conversation would follow the operator into a tab it does not belong to. Cleared
  // during render rather than in an effect — React restarts the render with the new state before
  // committing, so the stale row never paints. Same pattern as ConsoleHeader's mobile menu.
  const [filterAtRender, setFilterAtRender] = useState(activeFilter);
  if (filterAtRender !== activeFilter) {
    setFilterAtRender(activeFilter);
    setPinned(null);
  }

  const now = useMinute();

  const threads = useMemo(() => {
    const grouped: Thread[] = [];
    const index = new Map<string, number>();
    for (const r of requests) {
      const at = index.get(r.thread_id);
      if (at === undefined) {
        index.set(r.thread_id, grouped.length);
        grouped.push([r]);
      } else {
        grouped[at].push(r);
      }
    }

    // Only when the server has genuinely dropped it. Under the "all" filter it comes back with the
    // new status already on it, and the local copy is the stale one.
    if (pinned && !index.has(pinned[0].thread_id)) {
      const before = grouped.findIndex((t) => t[0].thread_last_at < pinned[0].thread_last_at);
      grouped.splice(before === -1 ? grouped.length : before, 0, pinned);
    }
    return grouped;
  }, [requests, pinned]);

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return threads;
    return threads.filter((thread) =>
      thread.some((m) =>
        [m.name, m.email, m.subject, m.message, m.category].some((field) =>
          field?.toLowerCase().includes(needle),
        ),
      ),
    );
  }, [threads, query]);

  // Falling back to the first conversation means the panel is never empty for no reason on a wide
  // screen. `explicit` stays false until something is actually clicked, which is what keeps the
  // phone layout on the list rather than opening the top conversation on arrival.
  const explicit = selectedId !== null;
  const selected = visible.find((t) => t[0].thread_id === selectedId) ?? visible[0] ?? null;

  function select(threadId: string) {
    if (pinned && pinned[0].thread_id !== threadId) setPinned(null);
    setSelectedId(threadId);
    // Deep-linkable without a round trip: replaceState updates the URL in place, so a conversation
    // can be linked to in a note or a message while clicking through the list stays instant.
    window.history.replaceState(null, "", `/admin/support?status=${activeFilter}&thread=${threadId}`);
  }

  function handleStatusChanged(thread: Thread, status: "open" | "closed") {
    setPinned(
      thread.map((m) => ({
        ...m,
        thread_status: status,
        thread_handled_at: status === "closed" ? new Date().toISOString() : null,
      })),
    );
    router.refresh();
  }

  const openCount = threads.filter((t) => t[0].thread_status === "open").length;

  return (
    <div className="flex h-[calc(100dvh-7.5rem)] min-h-[32rem] overflow-hidden rounded-xl border bg-card">
      {/* ------------------------------------------------------------------ list */}
      <aside
        className={cn(
          "flex w-full shrink-0 flex-col border-r md:w-[22rem]",
          explicit && "hidden md:flex",
        )}
      >
        <div className="space-y-3 border-b p-3">
          <div className="flex items-baseline justify-between gap-2 px-1">
            <h1 className="font-heading text-base font-semibold tracking-tight">Support</h1>
            <span className="text-xs text-muted-foreground">
              {openCount} open
            </span>
          </div>

          <div className="relative">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search conversations"
              aria-label="Search conversations"
              className="h-8 pl-8 text-sm"
            />
          </div>

          <div className="flex rounded-md bg-muted p-0.5">
            {FILTERS.map((f) => (
              <Link
                key={f}
                href={`/admin/support?status=${f}`}
                className={cn(
                  "flex-1 rounded-[5px] px-2 py-1 text-center text-xs font-medium capitalize transition-colors",
                  activeFilter === f
                    ? "bg-background text-foreground shadow-sm"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                {f}
              </Link>
            ))}
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {visible.length === 0 ? (
            <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center">
              <Inbox className="h-6 w-6 text-muted-foreground" />
              <p className="text-sm text-muted-foreground">
                {query
                  ? "Nothing matches that."
                  : activeFilter === "open"
                    ? "Nothing open."
                    : "Nothing here."}
              </p>
              {!query && activeFilter === "open" && (
                <p className="text-xs text-muted-foreground">
                  Only holds what has arrived since this shipped — anything earlier is in the
                  support inbox only.
                </p>
              )}
            </div>
          ) : (
            <ul>
              {visible.map((thread) => (
                <ThreadRow
                  key={thread[0].thread_id}
                  thread={thread}
                  now={now}
                  isSelected={selected?.[0].thread_id === thread[0].thread_id}
                  onSelect={() => select(thread[0].thread_id)}
                />
              ))}
            </ul>
          )}
        </div>
      </aside>

      {/* ---------------------------------------------------------- conversation */}
      <section className={cn("flex min-w-0 flex-1 flex-col", !explicit && "hidden md:flex")}>
        {selected ? (
          <Conversation
            // Remounts on selection, which is what resets the draft reply and the note to the
            // conversation being read rather than carrying the last one's text across.
            key={selected[0].thread_id}
            thread={selected}
            onBack={() => setSelectedId(null)}
            onStatusChanged={(status) => handleStatusChanged(selected, status)}
            onReplied={() => router.refresh()}
          />
        ) : (
          <div className="flex h-full items-center justify-center p-6 text-center text-sm text-muted-foreground">
            Select a conversation.
          </div>
        )}
      </section>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* List row                                                                    */
/* -------------------------------------------------------------------------- */

function ThreadRow({
  thread,
  now,
  isSelected,
  onSelect,
}: {
  thread: Thread;
  now: number | null;
  isSelected: boolean;
  onSelect: () => void;
}) {
  const latest = thread[0];
  const isOpen = latest.thread_status === "open";
  // Abuse reports are the ones with a clock on them — the app promises a response within 48 hours
  // and tells the reporter we never say they got in touch. Marked so they are not skimmed past.
  const urgent = thread.some((m) => m.category === "Report Abuse");
  // The state a support queue is actually sorted by in someone's head: they spoke last, and nobody
  // has answered.
  const needsReply = isOpen && latest.direction === "inbound";

  return (
    <li>
      <button
        type="button"
        onClick={onSelect}
        aria-current={isSelected}
        className={cn(
          "flex w-full gap-3 border-b px-3 py-3 text-left transition-colors hover:bg-accent/60",
          isSelected && "bg-accent",
          !isOpen && !isSelected && "opacity-70",
        )}
      >
        <span
          aria-hidden
          className={cn(
            "mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border text-xs font-semibold uppercase",
            urgent
              ? "border-destructive/40 bg-destructive/10 text-destructive"
              : "bg-muted text-muted-foreground",
          )}
        >
          {initial(latest)}
        </span>

        <span className="min-w-0 flex-1">
          <span className="flex items-baseline justify-between gap-2">
            <span className="truncate text-sm font-medium">
              {latest.name || latest.email || "Unknown sender"}
            </span>
            <span className="shrink-0 text-[11px] text-muted-foreground">
              {shortTime(latest.thread_last_at, now)}
            </span>
          </span>

          <span className="mt-0.5 flex items-center gap-1.5">
            {needsReply && (
              <span
                aria-label="Waiting on a reply"
                className="h-1.5 w-1.5 shrink-0 rounded-full bg-primary"
              />
            )}
            <span className="truncate text-sm text-foreground">
              {latest.subject || "(no subject)"}
            </span>
          </span>

          <span className="mt-0.5 block truncate text-xs text-muted-foreground">
            {latest.direction === "outbound" ? "You: " : ""}
            {preview(latest.message)}
          </span>

          <span className="mt-1.5 flex flex-wrap items-center gap-1">
            <Badge variant={urgent ? "destructive" : "secondary"} className="px-1.5 py-0 text-[10px]">
              {latest.category}
            </Badge>
            {thread.length > 1 && (
              <Badge variant="outline" className="px-1.5 py-0 text-[10px]">
                {thread.length}
              </Badge>
            )}
            {!isOpen && (
              <Badge variant="outline" className="px-1.5 py-0 text-[10px]">
                Closed
              </Badge>
            )}
          </span>
        </span>
      </button>
    </li>
  );
}

/* -------------------------------------------------------------------------- */
/* Conversation                                                                */
/* -------------------------------------------------------------------------- */

function Conversation({
  thread,
  onBack,
  onStatusChanged,
  onReplied,
}: {
  thread: Thread;
  onBack: () => void;
  onStatusChanged: (status: "open" | "closed") => void;
  onReplied: () => void;
}) {
  const latest = thread[0];
  // The RPC hands back newest first, which is right for the list and backwards for reading.
  const inOrder = useMemo(() => [...thread].reverse(), [thread]);
  const [note, setNote] = useState(latest.thread_handler_note ?? "");
  const [busy, setBusy] = useState<"open" | "closed" | null>(null);
  const isOpen = latest.thread_status === "open";
  const urgent = thread.some((m) => m.category === "Report Abuse");

  async function setStatus(status: "open" | "closed") {
    if (status === latest.thread_status) return;
    setBusy(status);
    const supabase = createClient();
    // One row, because status lives on the conversation now rather than being copied onto each of
    // its messages and kept in step by an UPDATE.
    const { error } = await supabase.rpc("admin_set_support_thread_status", {
      p_thread_id: latest.thread_id,
      p_status: status,
      p_note: nullableArg(note || null),
    });
    setBusy(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(status === "closed" ? "Conversation closed." : "Conversation reopened.");
    onStatusChanged(status);
  }

  return (
    <>
      <header className="flex items-start gap-3 border-b px-4 py-3">
        <Button
          variant="ghost"
          size="icon"
          className="-ml-1 h-8 w-8 shrink-0 md:hidden"
          aria-label="Back to conversations"
          onClick={onBack}
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="truncate text-sm font-semibold">{latest.subject || "(no subject)"}</h2>
            <Badge variant={urgent ? "destructive" : "secondary"} className="text-[10px]">
              {latest.category}
            </Badge>
            <Badge variant="outline" className="text-[10px]">
              {latest.source}
            </Badge>
          </div>
          <p className="mt-0.5 truncate text-xs text-muted-foreground">
            {latest.name ? `${latest.name} · ` : ""}
            {latest.email ?? "no address"}
            {latest.matched_profile_id ? (
              <>
                {" · "}
                <Link
                  href={`/admin/users/${latest.matched_profile_id}`}
                  className="underline underline-offset-2 hover:text-foreground"
                >
                  Open account
                </Link>
              </>
            ) : (
              // Worth saying rather than leaving blank: it usually means they wrote in from an
              // address they never signed up with, which is itself the answer to "why can't they
              // sign in".
              " · no matching account"
            )}
          </p>
        </div>

        {/* Both states shown at once rather than one button that swaps its label. The complaint
            this replaces was that reopening looked like it did nothing; a control that displays
            which state the conversation is in cannot look like that, because the answer is on
            screen before and after the click. */}
        <div
          className="flex shrink-0 rounded-md bg-muted p-0.5"
          role="group"
          aria-label="Conversation status"
        >
          {(["open", "closed"] as const).map((status) => (
            <button
              key={status}
              type="button"
              aria-pressed={latest.thread_status === status}
              disabled={busy !== null}
              onClick={() => setStatus(status)}
              className={cn(
                "flex items-center gap-1 rounded-[5px] px-2.5 py-1 text-xs font-medium capitalize transition-colors disabled:opacity-60",
                latest.thread_status === status
                  ? "bg-background text-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground",
              )}
            >
              {busy === status && <Loader2 className="h-3 w-3 animate-spin" />}
              {status}
            </button>
          ))}
        </div>
      </header>

      {latest.thread_handled_at && !isOpen && (
        <p className="border-b bg-muted/40 px-4 py-1.5 text-xs text-muted-foreground">
          Closed {formatDateTime(latest.thread_handled_at)}
          {latest.thread_handler_note ? ` — ${latest.thread_handler_note}` : ""}
        </p>
      )}

      <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-4 py-4">
        {inOrder.map((m) => (
          <Message key={m.id} message={m} />
        ))}
        <ThreadAttachments threadId={latest.thread_id} />
      </div>

      <div className="space-y-2 border-t p-3">
        <Composer threadId={latest.thread_id} to={latest.email} onSent={onReplied} />
        <Input
          className="h-8 text-xs"
          placeholder="Internal note — saved when you open or close this"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          disabled={busy !== null}
          aria-label="Internal note about how this was handled"
        />
      </div>
    </>
  );
}

function Message({ message }: { message: SupportRequest }) {
  const outbound = message.direction === "outbound";
  return (
    <div className={cn("flex", outbound && "justify-end")}>
      <div className={cn("max-w-[85%] min-w-0", outbound && "text-right")}>
        <p className="mb-1 px-1 text-[11px] text-muted-foreground">
          {outbound ? "You" : message.name || message.email || "Them"} ·{" "}
          {formatDateTime(message.created_at)}
        </p>
        <div
          className={cn(
            "whitespace-pre-wrap break-words rounded-lg px-3 py-2 text-left text-sm",
            outbound ? "bg-primary/10 text-foreground" : "bg-muted",
          )}
        >
          {message.message}
        </div>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Formatting                                                                  */
/* -------------------------------------------------------------------------- */

/**
 * The current time, rounded down to the minute — or null while rendering on the server.
 *
 * "3h" computed on the server and again in the browser are two different strings, and React calls
 * a disagreement like that a hydration error. A distinct server snapshot is the sanctioned answer:
 * the HTML carries an absolute date, the browser swaps in the relative one on hydration, and the
 * two never contradict each other because they were never asked to match.
 *
 * Rounded because `getSnapshot` must return the same value when called twice in one render.
 * `Date.now()` raw does not, and React re-renders indefinitely waiting for it to settle. A minute
 * is also the finest granularity anything here displays.
 */
function subscribeToClock(onChange: () => void) {
  const timer = setInterval(onChange, 30_000);
  return () => clearInterval(timer);
}

const clockSnapshot = () => Math.floor(Date.now() / 60_000) * 60_000;
const noClockOnServer = () => null;

function useMinute(): number | null {
  return useSyncExternalStore(subscribeToClock, clockSnapshot, noClockOnServer);
}

function initial(message: SupportRequest): string {
  const source = (message.name || message.email || "?").trim();
  return source.charAt(0) || "?";
}

function preview(message: string): string {
  return message.replace(/\s+/g, " ").trim() || "(empty)";
}

function formatDateTime(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

/** Short enough for a list column. Absolute until mounted — see `now` in SupportQueue. */
function shortTime(value: string, now: number | null): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  if (now === null) return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });

  const minutes = Math.round((now - date.getTime()) / 60_000);
  if (minutes < 1) return "now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.round(hours / 24);
  if (days < 7) return `${days}d`;
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

/* -------------------------------------------------------------------------- */
/* Composer                                                                    */
/* -------------------------------------------------------------------------- */

/**
 * Replying, from the same screen the conversation is read on.
 *
 * "Close after sending" defaults on, because answering usually is the resolution — but it is a
 * choice rather than an assumption, since a reply asking for a screenshot leaves the conversation
 * very much open.
 *
 * The recipient is shown rather than editable. It comes from the thread, and letting it be typed
 * would turn a support console into a way to send mail from the company address to anywhere.
 */
function Composer({
  threadId,
  to,
  onSent,
}: {
  threadId: string;
  to: string | null;
  onSent: () => void;
}) {
  const [body, setBody] = useState("");
  const [close, setClose] = useState(true);
  const [sending, setSending] = useState(false);
  const [files, setFiles] = useState<{ id: string; name: string }[]>([]);
  const [uploading, setUploading] = useState(false);

  /// Two steps, because the file never passes through our servers: reserve a key and a signed PUT,
  /// then upload straight to R2. An edge function in the middle would hold the whole file in memory
  /// for no benefit and against tighter limits than the bucket's.
  async function addFile(file: File) {
    setUploading(true);
    const supabase = createClient();
    try {
      const { data, error } = await supabase.functions.invoke("support-attachment-upload", {
        body: { threadId, filename: file.name, contentType: file.type, size: file.size },
      });
      if (error || !data?.uploadUrl) {
        // The RPC's own message — the size ceiling, the pending-file limit — is more use than a
        // generic refusal, so it is surfaced rather than replaced. It arrives on the error, not in
        // `data`, which is null for every non-2xx; see functionErrorMessage.
        toast.error(await functionErrorMessage(error, "Couldn't prepare that upload."));
        return;
      }
      const put = await fetch(data.uploadUrl, {
        method: "PUT",
        // Must match what was signed: R2 rejects a PUT whose type differs from the authorised one.
        headers: { "Content-Type": data.contentType },
        body: file,
      });
      if (!put.ok) {
        toast.error("That file didn't upload.");
        return;
      }
      setFiles((f) => [...f, { id: data.id, name: file.name }]);
    } finally {
      setUploading(false);
    }
  }

  async function send() {
    setSending(true);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("send-support-reply", {
      body: { threadId, body, close, attachmentIds: files.map((f) => f.id) },
    });
    setSending(false);

    if (error || !data?.ok) {
      // The function distinguishes "not authorised", "no address to reply to", "email sending
      // isn't set up" and "SMTP refused it" — and only the last of those is worth retrying. One
      // message for all four sent the operator back to the same button every time.
      toast.error(await functionErrorMessage(error, "Couldn't send that reply."));
      return;
    }
    // The function reports this when the mail went but the conversation could not be updated.
    // Saying "sent" alone would invite a second one.
    if (data.recorded === false) {
      toast.warning(data.warning ?? "Sent, but the conversation wasn't updated. Don't resend.");
    } else {
      toast.success(close ? "Replied and closed." : "Replied.");
    }
    setBody("");
    setFiles([]);
    onSent();
  }

  if (!to) {
    return (
      <p className="px-1 py-2 text-xs text-muted-foreground">
        No address on this conversation, so there is nothing to reply to.
      </p>
    );
  }

  return (
    <div className="rounded-lg border bg-background focus-within:ring-1 focus-within:ring-ring">
      <Textarea
        rows={3}
        placeholder={`Reply to ${to}…`}
        value={body}
        onChange={(e) => setBody(e.target.value)}
        disabled={sending}
        aria-label="Reply"
        className="resize-none border-0 bg-transparent shadow-none focus-visible:ring-0"
      />

      {files.length > 0 && (
        <ul className="flex flex-wrap gap-2 px-3 pb-2">
          {files.map((f) => (
            <li key={f.id} className="flex items-center gap-1.5 rounded-md border px-2 py-1 text-xs">
              <Paperclip className="h-3 w-3 text-muted-foreground" />
              <span className="max-w-[16rem] truncate">{f.name}</span>
              <button
                type="button"
                aria-label={`Remove ${f.name}`}
                onClick={() => setFiles((list) => list.filter((x) => x.id !== f.id))}
                disabled={sending}
                className="text-muted-foreground hover:text-foreground"
              >
                <X className="h-3 w-3" />
              </button>
            </li>
          ))}
        </ul>
      )}

      <div className="flex flex-wrap items-center justify-between gap-3 border-t px-2 py-1.5">
        <div className="flex items-center gap-3">
          <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-md px-1.5 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground">
            {uploading ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              <Paperclip className="h-3.5 w-3.5" />
            )}
            Attach
            <input
              type="file"
              className="sr-only"
              disabled={sending || uploading || files.length >= 5}
              onChange={(e) => {
                const file = e.target.files?.[0];
                // Cleared so the same file can be picked twice — otherwise re-selecting it after a
                // failed upload fires no change event at all.
                e.target.value = "";
                if (file) void addFile(file);
              }}
            />
          </label>
          <Switch
            id={`close-${threadId}`}
            checked={close}
            onCheckedChange={setClose}
            disabled={sending}
          />
          <Label htmlFor={`close-${threadId}`} className="text-xs font-normal text-muted-foreground">
            Close after sending
          </Label>
        </div>
        <Button size="sm" disabled={sending || body.trim().length < 2} onClick={send}>
          {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          Send
        </Button>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Attachments                                                                 */
/* -------------------------------------------------------------------------- */

interface ThreadAttachment {
  id: string;
  filename: string;
  content_type: string;
  size_bytes: number | null;
  direction: string;
}

/**
 * Files on the conversation, theirs and ours.
 *
 * Inbound ones arrive by a different route from everything else on this screen: Zoho's webhook
 * carries no attachments, so `fetch-support-attachments` collects them from the Mail API a few
 * minutes later. A message can therefore be readable before its screenshot is — which is why an
 * empty list here is silent rather than saying "no attachments", since that would be wrong for the
 * first few minutes of every message that has one.
 *
 * Downloads are signed on demand and expire in minutes. A support attachment is somebody's private
 * correspondence, and a URL that outlives the click is one that outlives the reason for it.
 */
function ThreadAttachments({ threadId }: { threadId: string }) {
  const [files, setFiles] = useState<ThreadAttachment[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const supabase = createClient();
      const { data } = await supabase.rpc("admin_thread_attachments", { p_thread_id: threadId });
      if (!cancelled) setFiles((data ?? []) as ThreadAttachment[]);
    })();
    return () => {
      cancelled = true;
    };
  }, [threadId]);

  async function open(file: ThreadAttachment) {
    setBusy(file.id);
    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("support-attachment-upload", {
      body: { threadId, attachmentId: file.id },
    });
    setBusy(null);
    if (error || !data?.url) {
      toast.error(await functionErrorMessage(error, "Couldn't open that file."));
      return;
    }
    window.open(data.url, "_blank", "noopener,noreferrer");
  }

  if (files.length === 0) return null;

  return (
    <div className="space-y-1.5 border-t pt-3">
      <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Files</p>
      <ul className="flex flex-wrap gap-2">
        {files.map((file) => (
          <li key={file.id}>
            <button
              type="button"
              onClick={() => open(file)}
              disabled={busy === file.id}
              className="flex items-center gap-1.5 rounded-md border px-2 py-1 text-xs transition-colors hover:bg-accent"
            >
              {busy === file.id ? (
                <Loader2 className="h-3 w-3 animate-spin" />
              ) : file.direction === "inbound" ? (
                <Download className="h-3 w-3 text-muted-foreground" />
              ) : (
                <Paperclip className="h-3 w-3 text-muted-foreground" />
              )}
              <span className="max-w-[16rem] truncate">{file.filename}</span>
              {file.size_bytes ? (
                <span className="text-muted-foreground">{formatBytes(file.size_bytes)}</span>
              ) : null}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
