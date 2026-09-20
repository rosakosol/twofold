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
          description), and both documents currently hide it.

          `doc === null` no longer means "nothing published yet" — both are published, so it means
          the fetch failed and the reader is looking at the short fallback instead of the real
          document. The notice says that, rather than the draft warning it used to carry, which
          would now tell someone a reviewed policy is an unreviewed placeholder. */}
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
