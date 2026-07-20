"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { Bookmark, LogOut, User as UserIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
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

function avatarUrl(userId: string, supabaseUrl: string) {
  return `${supabaseUrl}/storage/v1/object/public/avatars/${userId}/avatar.jpg`;
}

export function UserMenu() {
  const { user, isLoading } = useUser();
  const router = useRouter();

  if (isLoading) return <Skeleton className="h-9 w-9 rounded-full" />;

  if (!user) {
    return <Button size="sm" render={<Link href="/auth/sign-in">Sign in</Link>} />;
  }

  const email = user.email ?? "";
  const initials = email.slice(0, 2).toUpperCase();

  async function handleSignOut() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.refresh();
  }

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button variant="ghost" size="icon" className="rounded-full">
            <Avatar className="h-8 w-8">
              <AvatarImage
                src={avatarUrl(user.id, process.env.NEXT_PUBLIC_SUPABASE_URL!)}
                alt=""
              />
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
            <Link href="/bookmarks">
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
  );
}
