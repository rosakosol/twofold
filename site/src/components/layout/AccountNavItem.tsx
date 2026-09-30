"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useUser } from "@/lib/auth/useUser";

/**
 * "Account" in the collapsed nav menu, for someone who is signed in.
 *
 * Both navbars put the account page behind the avatar's dropdown, which works on a wide screen
 * where the avatar sits next to your email address. Below the breakpoint that menu collapses, the
 * email is hidden (`.site-nav-email`) and the avatar is a circle of initials that does not say
 * what it opens — so on a phone the account page was reachable only by guessing. This is the named
 * row, `.site-nav-account` in site-nav.css hides it again on desktop.
 *
 * Only for a signed-in visitor. Signed out, `UserMenu` renders the "Sign in" pill, which is in
 * `.site-nav-actions` and stays visible at every width, so there is already a door and a second
 * one in the collapsed list would be noise.
 *
 * Renders the `<li>` itself because it belongs inside `.site-nav-links`, which is the `<ul>` the
 * collapsed menu is built from — the styling for a row comes from that list, not from here.
 */
export function AccountNavItem() {
  const pathname = usePathname();
  const { user } = useUser();

  if (!user) return null;

  return (
    <li className="site-nav-account">
      <Link href="/account" className={pathname === "/account" ? "is-active" : undefined}>
        Account
      </Link>
    </li>
  );
}
