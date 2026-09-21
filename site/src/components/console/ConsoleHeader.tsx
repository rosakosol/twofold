"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { UserMenu } from "@/components/layout/UserMenu";
import { useAdminRoles } from "@/lib/auth/useAdminRoles";

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
  // The admin view of the public feedback board — status, merge, pin, developer updates. Named
  // "Feedback" rather than "Requests" because it sat beside "Support" and both read as inbound
  // asks; this one is the public board people vote on, Support is private correspondence.
  //
  // Distinct from /feedback itself, which stays in the website's nav: the privacy policy describes
  // that board as readable by anyone, signed in or not, and it is where users post and vote.
  { href: "/admin", label: "Feedback", exact: true },
  // Accounts. Its own role, because reading somebody's email, partner and subscription is a
  // narrower grant than editing a deck — see 20261109000000.
  { href: "/admin/support", label: "Support", exact: false, role: "support" as const },
  { href: "/admin/users", label: "Users", exact: false, role: "support" as const },
  // Blocks, and an honest note about why there is no report queue.
  { href: "/admin/moderation", label: "Moderation", exact: false, role: "support" as const },
  { href: "/admin/games", label: "Games", exact: false },
  // Spend. Its own role, so its own visibility — see useIsBillingAdmin below.
  { href: "/admin/usage", label: "Usage", exact: false, role: "billing" as const },
  // Sanity Studio renders its own full-viewport chrome and is not wrapped by this layout, so this
  // is a link out rather than a tab that keeps the bar on screen.
  { href: "/studio", label: "Studio", exact: false },
];

export function ConsoleHeader() {
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
        <Link className="site-nav-brand" href="/admin">
          {/* eslint-disable-next-line @next/next/no-img-element -- fixed-size brand mark, matches SiteHeader's */}
          <img src="/assets/globe-heart.png" alt="" width={28} height={28} />
          <span>
            twofold <span className="site-nav-brand-tag">console</span>
          </span>
        </Link>

        <nav>
          <ul className="site-nav-links">
            {CONSOLE_LINKS.filter((link) =>
              link.role === "billing" ? roles.billing : link.role === "support" ? roles.support : true,
            ).map((link) => {
              const isActive = link.exact ? pathname === link.href : pathname.startsWith(link.href);
              return (
                <li key={link.href}>
                  <Link href={link.href} className={isActive ? "is-active" : undefined}>
                    {link.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="site-nav-actions">
          <Link href="/" className="site-nav-switch">
            <ArrowLeft className="h-3.5 w-3.5" />
            <span>Website</span>
          </Link>
          <UserMenu />
          {/* Without this the console's links are unreachable below 860px: site-nav.css hides
              `.site-nav-links` there unless the bar carries `.is-open`. */}
          <button
            type="button"
            className="site-nav-toggle"
            aria-label="Toggle menu"
            aria-expanded={isOpen}
            onClick={() => setIsOpen((v) => !v)}
          >
            <svg className="icon icon-menu">
              <use href="/assets/icons.svg#icon-menu" />
            </svg>
            <svg className="icon icon-x">
              <use href="/assets/icons.svg#icon-x" />
            </svg>
          </button>
        </div>
      </div>
    </header>
  );
}
