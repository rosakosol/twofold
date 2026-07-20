"use client";

import { useRouter, usePathname } from "next/navigation";
import { Bell, BellRing } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useUser } from "@/lib/auth/useUser";
import { useIsSubscribed, useToggleSubscribe } from "@/lib/queries/useSubscribe";

export function SubscribeButton({ featureId }: { featureId: string }) {
  const { user } = useUser();
  const router = useRouter();
  const pathname = usePathname();
  const { data: isSubscribed } = useIsSubscribed(featureId, user?.id);
  const toggle = useToggleSubscribe(featureId);

  function handleClick() {
    if (!user) {
      router.push(`/auth/sign-in?next=${encodeURIComponent(pathname)}`);
      return;
    }
    toggle.mutate({ userId: user.id, isSubscribed: !!isSubscribed });
  }

  return (
    <Button variant="outline" size="sm" onClick={handleClick} disabled={toggle.isPending}>
      {isSubscribed ? <BellRing className="h-4 w-4" /> : <Bell className="h-4 w-4" />}
      {isSubscribed ? "Subscribed" : "Subscribe"}
    </Button>
  );
}
