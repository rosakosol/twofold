import { PortableText } from "@portabletext/react";
import type { LegalPageDoc } from "@/lib/marketing/sanity";

function formatLastUpdated(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { day: "numeric", month: "long", year: "numeric" });
}

export function LegalPageLayout({
  doc,
  fallbackTitle,
  fallbackLastUpdated,
  fallbackNotice,
  children,
}: {
  doc: LegalPageDoc | null;
  fallbackTitle: string;
  fallbackLastUpdated: string;
  fallbackNotice: React.ReactNode;
  /** Hardcoded JSX body, used only when Sanity has no `body` published yet. */
  children: React.ReactNode;
}) {
  const title = doc?.title || fallbackTitle;
  const lastUpdated = doc?.lastUpdated ? formatLastUpdated(doc.lastUpdated) : fallbackLastUpdated;
  const noticeText = doc?.noticeText;

  return (
    <main className="legal-wrap">
      <h1>{title}</h1>
      <p>
        <em>Last updated: {lastUpdated}</em>
      </p>

      {/* Sanity's noticeText is empty-string-hideable (see legalPage.ts's own field
          description); doc === null (nothing published yet) falls back to the
          hardcoded draft notice so the page doesn't silently look "final". */}
      {(doc === null || noticeText) && (
        <div className="legal-notice">
          <svg className="icon">
            <use href="/assets/icons.svg#icon-shield" />
          </svg>
          <span>{noticeText || fallbackNotice}</span>
        </div>
      )}

      <div id="legal-body">{doc?.body ? <PortableText value={doc.body} /> : children}</div>
    </main>
  );
}
