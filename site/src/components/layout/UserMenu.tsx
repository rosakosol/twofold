"use client";

import Link from "next/link";
import { Bookmark, LogOut, Settings, User as UserIcon } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { useUser } from "@/lib/auth/useUser";
import { signOutAndGoHome } from "@/lib/auth/signOutAndGoHome";
import { APP_STORE_URL } from "@/lib/marketing/config";

// There used to be an `avatarUrl()` here building
// `${supabaseUrl}/storage/v1/object/public/avatars/${userId}/avatar.jpg`. It never worked: the
// `avatars` bucket stopped being public in 20260722010000, so that URL had been 404ing on every
// page load and the fallback initials below were always what rendered. Avatars have since moved to
// R2 and the bucket is empty, so it is doubly gone.
//
// Not replaced, rather than replaced badly. Reaching a private avatar now means asking the
// `storage-url` Edge Function for a presigned URL with the viewer's session — a client-side round
// trip on every page load, for a decoration in a dropdown that already reads fine as initials. If
// it is ever wanted, that is the way to do it, and `R2Storage.readURL` in the iOS app is the shape.

export function UserMenu() {
  const { user, isLoading } = useUser();

  if (isLoading) return <Skeleton className="h-11 w-11 rounded-full" />;

  if (!user) {
    // Download is the header's action (docs/TWOFOLD_WEBSITE.md, section 3). Sign in stays beside
    // it as a quiet link, because it is the only way into the account page and the console; on a
    // phone it moves into the menu (SignedInNavItems).
    return (
      <>
        <Link href="/auth/sign-in" className="site-nav-signin">
          Sign in
        </Link>
        <a href={APP_STORE_URL} data-appstore-link className="btn btn-primary btn-sm">
          Download
        </a>
      </>
    );
  }

  const email = user.email ?? "";
  const initials = email.slice(0, 2).toUpperCase();

  async function handleSignOut() {
    await signOutAndGoHome();
  }

  return (
    <>
      <DropdownMenu>
        {/* The account chip: your email and your initials in one pill, opening the account menu.
            On a phone the email is hidden and the chip is the initials alone. */}
        <DropdownMenuTrigger
          render={
            <button type="button" className="account-chip" aria-label={`Account menu, ${email}`}>
              <span className="account-chip-email">{email}</span>
              <span className="account-chip-avatar" aria-hidden>
                {initials}
              </span>
            </button>
          }
        />
        <DropdownMenuContent align="end" className="w-56">
          <div className="px-2 py-1.5 text-sm text-muted-foreground truncate flex items-center gap-2">
            <UserIcon className="h-4 w-4" />
            {email}
          </div>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            render={
              <Link href="/account">
                <Settings className="h-4 w-4" />
                Your account
              </Link>
            }
          />
          <DropdownMenuItem
            render={
              <Link href="/feedback/bookmarks">
                <Bookmark className="h-4 w-4" />
                Your bookmarks
              </Link>
            }
          />
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={handleSignOut} variant="destructive">
            <LogOut className="h-4 w-4" />
            Sign out
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </>
  );
}
