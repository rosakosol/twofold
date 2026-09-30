"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useUser } from "@/lib/auth/useUser";

/** The destinations that only exist for a signed-in visitor, and only by name in the collapsed
 *  menu — the same two the avatar's dropdown lists, in the same order. */
const LINKS = [
  { href: "/account", label: "Account" },
  { href: "/feedback/bookmarks", label: "Bookmarks" },
];

/**
 * "Account" and "Bookmarks" in the collapsed nav menu, for someone who is signed in.
 *
 * All three navbars put these behind the avatar's dropdown, which reads fine on a wide screen
 * where the avatar sits beside your email address. Collapsed, `.site-nav-email` is hidden and the
 * avatar is a circle of initials with nothing saying what it opens — so on a phone both pages were
 * reachable only by guessing that the circle was a menu.
 *
 * Only for a signed-in visitor. Signed out, `UserMenu` renders the "Sign in" pill, which is in
 * `.site-nav-actions` and stays visible at every width, so there is already a door and more of
 * them in the collapsed list would be noise.
 *
 * One component rather than one per row, so the list stays in step with the dropdown and there is
 * a single `useUser` subscriber behind both.
 *
 * Renders the `<li>`s itself because they belong inside `.site-nav-links`, the `<ul>` the collapsed
 * menu is built from — what a row looks like comes from that list, not from here.
 */
export function SignedInNavItems() {
  const pathname = usePathname();
  const { user } = useUser();

  if (!user) return null;

  return (
    <>
      {LINKS.map((link) => (
        <li key={link.href} className="site-nav-signed-in">
          <Link href={link.href} className={pathname === link.href ? "is-active" : undefined}>
            {link.label}
          </Link>
        </li>
      ))}
    </>
  );
}
