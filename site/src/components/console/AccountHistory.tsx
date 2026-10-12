"use client";

import { useState } from "react";
import { History } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { AuditEntry } from "@/lib/console/accountDetail";
import { shortDateTime } from "@/lib/console/format";
import { AccountSection } from "@/components/console/AccountLayout";

/** Rows shown before "Show all". Mostly `account.view`, so ten is a screen of it. */
const SHOWN = 10;

/**
 * What admins have done to and seen of this account, newest first, from `admin_audit_for_subject`.
 * Opening the page is itself one of the rows, which is why the list is mostly views.
 */
export function AccountHistory({ entries, limit }: { entries: AuditEntry[]; limit: number }) {
  const [all, setAll] = useState(false);
  const shown = all ? entries : entries.slice(0, SHOWN);

  return (
    <AccountSection
      id="history"
      title="Admin history"
      icon={<History aria-hidden className="text-muted-foreground" />}
      description="Opening this page is recorded. The log is append-only."
      className="account-history"
    >
      <div className="account-card">
        {entries.length === 0 ? (
          <p className="account-empty-line">Nothing recorded.</p>
        ) : (
          <table className="console-table">
            <thead>
              <tr>
                <th scope="col">Action</th>
                <th scope="col">By</th>
                <th scope="col">When</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((entry, i) => (
                <tr key={i}>
                  <td>
                    <span className="console-mono">{entry.action}</span>
                    {entry.reason && <p className="account-history-reason">{entry.reason}</p>}
                  </td>
                  <td className="account-history-by">{entry.actor_email ?? entry.actor_id}</td>
                  <td className="muted">{shortDateTime(entry.occurred_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
        {(entries.length > SHOWN || entries.length >= limit) && (
          <div className="account-history-more">
            <span>
              {all || entries.length <= SHOWN
                ? entries.length >= limit
                  ? `The newest ${limit} load here.`
                  : `All ${entries.length}.`
                : `Newest ${SHOWN} of ${entries.length}${entries.length >= limit ? " loaded" : ""}.`}
            </span>
            {entries.length > SHOWN && (
              <Button variant="ghost" size="sm" onClick={() => setAll((v) => !v)} aria-expanded={all}>
                {all ? "Show fewer" : "Show all"}
              </Button>
            )}
          </div>
        )}
      </div>
    </AccountSection>
  );
}
