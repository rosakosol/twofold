import Link from "next/link";

const COLUMNS = [
  {
    heading: "Product",
    links: [
      { href: "/features", label: "Features" },
      { href: "/pricing", label: "Pricing" },
      { href: "/feedback", label: "Feedback" },
    ],
  },
  {
    heading: "Support",
    links: [
      { href: "/support", label: "Contact us" },
      { href: "/faq", label: "FAQ" },
    ],
  },
  {
    heading: "Legal",
    links: [
      { href: "/privacy", label: "Privacy Policy" },
      { href: "/terms", label: "Terms of Use" },
    ],
  },
];

/** The footer every page shares (docs/TWOFOLD_WEBSITE.md, section 3). */
export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="site-footer-inner">
        <div className="site-footer-brand">
          <Link href="/" className="site-footer-wordmark" aria-label="Twofold home">
            {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark */}
            <img src="/assets/globe-heart.png" alt="" width={26} height={26} />
            <span aria-hidden>twofold</span>
          </Link>
          <p>The living map for long-distance couples. Track flights, close the distance, keep the memories.</p>
        </div>
        {COLUMNS.map((column) => (
          <nav key={column.heading} className="site-footer-col" aria-label={column.heading}>
            <h2>{column.heading}</h2>
            <ul>
              {column.links.map((link) => (
                <li key={link.href}>
                  <Link href={link.href}>{link.label}</Link>
                </li>
              ))}
            </ul>
          </nav>
        ))}
      </div>
      <div className="site-footer-base">
        <div className="site-footer-base-row">
          <span>&copy; {new Date().getFullYear()} Twofold. Made for the couples doing long distance.</span>
          <span>twofoldapp.com.au</span>
        </div>
      </div>
    </footer>
  );
}
