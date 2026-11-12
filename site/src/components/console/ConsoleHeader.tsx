"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ArrowLeft, ExternalLink, Menu, X } from "lucide-react";
import { UserMenu } from "@/components/layout/UserMenu";
import { SignedInNavItems } from "@/components/layout/SignedInNavItems";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import { useAdminRoles } from "@/lib/auth/useAdminRoles";
import { Wordmark } from "@/components/layout/Wordmark";
import { STUDIO_URL } from "@/lib/studio";

/**
 * The console's own navbar, and the reason it is not `SiteHeader`.
 *
 * The admin links used to live inside `SiteHeader` behind an `isAdmin` check, which made the
 * public site and the internal tools one surface with some items hidden. Two things were wrong
 * with that. An admin browsing the marketing site carried a row of internal links across every
 * page, including pages a visitor might be reading over their shoulder. And nothing told you which
 * context you were in — /pricing and /admin/games wore the same navbar, so "am I about to change
 * something customers see" was a question the interface never answered.
 *
 * So the console is its own shell with its own header, and the two are crossed deliberately by a
 * single button rather than drifted between by a link that happens to be in the bar. It reuses
 * `.site-nav` markup so spacing and scroll behaviour match, but the bar is tinted and the wordmark
 * carries a tag, because looking identical was the problem.
 *
 * Deliberately no SiteFooter below it: marketing links and legal pages belong on the site, not
 * under a deck editor.
 */
const CONSOLE_LINKS = [
  // The admin view of the public feedback board — status, merge, pin, edit. Named
  // "Feedback" rather than "Requests" because it sat beside "Support" and both read as inbound
  // asks; this one is the public board people vote on, Support is private correspondence.
  //
  // Distinct from /feedback itself, which stays in the website's nav: the privacy policy describes
  // that board as readable by anyone, signed in or not, and it is where users post and vote.
  //
  // Feedback, Games and Studio are the content role's: their writes are `is_feedback_admin()`,
  // which is role = 'content' (20261109000000). Shown to a support- or billing-only admin they were
  // tabs whose every save failed.
  { href: "/admin", label: "Feedback", exact: true, role: "content" as const },
  // Accounts. Its own role, because reading somebody's email, partner and subscription is a
  // narrower grant than editing a deck — see 20261109000000.
  { href: "/admin/support", label: "Support", exact: false, role: "support" as const },
  { href: "/admin/users", label: "Users", exact: false, role: "support" as const },
  // Blocks, and an honest note about why there is no report queue.
  { href: "/admin/moderation", label: "Moderation", exact: false, role: "support" as const },
  // What admins have done and read (20261124000700).
  { href: "/admin/activity", label: "Activity", exact: false, role: "support" as const },
  { href: "/admin/games", label: "Games", exact: false, role: "content" as const },
  // The FAQ shared with the app's Support screen. It was a tool inside Studio (see useFaqEntries.ts).
  { href: "/admin/faq", label: "FAQ", exact: false, role: "content" as const },
  // Spend. Its own role, so its own visibility — see useIsBillingAdmin below.
  { href: "/admin/usage", label: "Usage", exact: false, role: "billing" as const },
  // Sanity Studio, on Sanity's own hosting (lib/studio.ts), so a link out in a new tab.
  { href: STUDIO_URL, label: "Studio", exact: false, role: "content" as const },
];

/** `showLinks` is off at /admin/mfa, where none of the tabs would open anything yet. */
export function ConsoleHeader({ showLinks = true }: { showLinks?: boolean }) {
  const pathname = usePathname();
  const roles = useAdminRoles();
  const [isScrolled, setIsScrolled] = useState(false);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    function handleScroll() {
      setIsScrolled(window.scrollY > 8);
    }
    handleScroll();
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  // Close the mobile menu on navigation, during render rather than in an effect — same reasoning
  // as SiteHeader: React restarts the render with the new state before committing, so the menu
  // never paints open on the destination route.
  const [menuPathname, setMenuPathname] = useState(pathname);
  if (menuPathname !== pathname) {
    setMenuPathname(pathname);
    setIsOpen(false);
  }

  return (
    <header className={`site-nav is-console${isScrolled ? " is-scrolled" : ""}${isOpen ? " is-open" : ""}`}>
      <div className="site-nav-inner">
        <Link className="site-nav-brand" href="/admin" aria-label="Twofold console">
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark, matches SiteHeader's */}
          <img src="/assets/globe-heart.png" alt="" width={28} height={28} />
          <Wordmark />
          <span className="site-nav-brand-tag">Console</span>
        </Link>

        <nav aria-label="Console">
          <ul className="site-nav-links">
            {CONSOLE_LINKS.filter((link) => showLinks && roles[link.role]).map((link) => {
              const isActive = link.exact ? pathname === link.href : pathname.startsWith(link.href);
              return (
                <li key={link.href}>
                  {link.href === STUDIO_URL ? (
                    // Studio is another site, so it opens in a new tab and says so.
                    <a href={link.href} className="site-nav-external" target="_blank" rel="noopener noreferrer">
                      {link.label}
                      <ExternalLink aria-hidden />
                      <span className="sr-only">(opens Sanity Studio in a new tab)</span>
                    </a>
                  ) : (
                    <Link href={link.href} aria-current={isActive ? "page" : undefined}>
                      {link.label}
                    </Link>
                  )}
                </li>
              );
            })}
            {/* The same collapsed-menu gap as the other two navbars: this bar renders the same
                UserMenu, so on a phone these were behind an unlabelled avatar here too. */}
            <SignedInNavItems />
            <ThemeToggle variant="menu-row" />
          </ul>
        </nav>

        <div className="site-nav-actions">
          <Link href="/" className="site-nav-switch">
            <ArrowLeft aria-hidden />
            <span>Website</span>
          </Link>
          <ThemeToggle />
          <UserMenu />
          {/* Without this the console's links are unreachable below 860px: site-nav.css hides
              `.site-nav-links` there unless the bar carries `.is-open`. */}
          <button
            type="button"
            className="site-nav-toggle"
            aria-label={isOpen ? "Close menu" : "Open menu"}
            aria-expanded={isOpen}
            onClick={() => setIsOpen((v) => !v)}
          >
            {isOpen ? <X aria-hidden /> : <Menu aria-hidden />}
          </button>
        </div>
      </div>
    </header>
  );
}
