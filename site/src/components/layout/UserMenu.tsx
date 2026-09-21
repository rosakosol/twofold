"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Bookmark, LogOut, Settings, User as UserIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { useUser } from "@/lib/auth/useUser";
import { createClient } from "@/lib/supabase/client";

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
  const router = useRouter();

  if (isLoading) return <Skeleton className="h-9 w-9 rounded-full" />;

  if (!user) {
    // Styled as the same pill CTA as the marketing navbar's "Get the App" button
    // (`.site-nav-cta`, from src/styles/site-nav.css) rather than the shadcn Button,
    // so the two navbars' right-side action matches exactly, not just approximately.
    return (
      <Link href="/auth/sign-in" className="site-nav-cta">
        Sign in
      </Link>
    );
  }

  const email = user.email ?? "";
  const initials = email.slice(0, 2).toUpperCase();

  async function handleSignOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.refresh();
  }

  return (
    <>
      <span className="site-nav-email" title={email}>
        {email}
      </span>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button variant="ghost" size="icon" className="rounded-full" aria-label={email}>
              <Avatar className="h-8 w-8">
                <AvatarFallback>{initials}</AvatarFallback>
              </Avatar>
            </Button>
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
