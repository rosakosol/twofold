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
  status: string;
  handler_note: string | null;
  handled_at: string | null;
  created_at: string;
}

/**
 * Two states, open and closed, and no workflow beyond that. A queue one person works needs to
 * answer "is this dealt with"; every additional state is one more thing to keep accurate by hand,
 * and an inaccurate status is worse than none because it gets trusted.
 *
 * The message is shown in full rather than truncated behind a click. These are short by
 * construction — both forms cap at 5000 characters and most are a paragraph — and a support queue
 * where reading the request takes an extra interaction is one where the first line gets skimmed
 * and the actual question missed.
 */
export function SupportQueue({
  requests,
  activeFilter,
}: {
  requests: SupportRequest[];
  activeFilter: string;
}) {
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

      {requests.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            {activeFilter === "open"
              ? "Nothing open. Note that this only holds requests sent since it shipped — anything earlier is in the support inbox only."
              : "Nothing here."}
          </CardContent>
        </Card>
      ) : (
        <ul className="space-y-3">
          {requests.map((request) => (
            <RequestCard key={request.id} request={request} />
          ))}
        </ul>
      )}
    </div>
  );
}

function RequestCard({ request }: { request: SupportRequest }) {
  const router = useRouter();
  const [note, setNote] = useState(request.handler_note ?? "");
  const [busy, setBusy] = useState(false);
  const isOpen = request.status === "open";

  async function setStatus(status: "open" | "closed") {
    setBusy(true);
    const supabase = createClient();
    const { error } = await supabase.rpc("admin_set_support_request_status", {
      p_id: request.id,
      p_status: status,
      p_note: nullableArg(note || null),
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(status === "closed" ? "Closed." : "Reopened.");
    router.refresh();
  }

  // Abuse reports are the ones with a clock on them — the app promises a response within 48 hours
  // and tells the reporter we never say they got in touch. Marked so they are not skimmed past.
  const urgent = request.category === "Report Abuse";

  return (
    <li>
      <Card className={urgent && isOpen ? "border-destructive/50" : undefined}>
        <CardContent className="space-y-3 pt-6">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant={urgent ? "destructive" : "secondary"}>{request.category}</Badge>
                <Badge variant="outline">{request.source}</Badge>
                {!isOpen && <Badge variant="outline">closed</Badge>}
              </div>
              <p className="mt-1.5 text-sm font-medium">
                {request.subject || "(no subject)"}
              </p>
              <p className="text-xs text-muted-foreground">
                {request.name ? `${request.name} · ` : ""}
                {request.email ?? "no address"} · {formatDateTime(request.created_at)}
              </p>
            </div>

            {request.matched_profile_id ? (
              <Link
                href={`/admin/users/${request.matched_profile_id}`}
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

          <p className="whitespace-pre-wrap rounded-md bg-muted/50 p-3 text-sm">{request.message}</p>

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
            {request.handled_at && (
              <span className="text-xs text-muted-foreground">
                closed {formatDateTime(request.handled_at)}
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
