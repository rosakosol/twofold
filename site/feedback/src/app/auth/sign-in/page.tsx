"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { BASE_PATH } from "@/lib/basePath";
import { Loader2, Mail } from "lucide-react";

export default function SignInPage() {
  return (
    <Suspense>
      <SignInForm />
    </Suspense>
  );
}

function SignInForm() {
  const searchParams = useSearchParams();
  const next = searchParams.get("next") ?? "/";

  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState("");
  const [isGoogleLoading, setIsGoogleLoading] = useState(false);

  function callbackUrl() {
    // `basePath` only auto-prefixes Next's own routing helpers (Link, router.push) —
    // this manually-built URL string needs the /feedback prefix spelled out explicitly.
    const site = process.env.NEXT_PUBLIC_SITE_URL ?? window.location.origin;
    const url = new URL(`${BASE_PATH}/auth/callback`, site);
    url.searchParams.set("next", next);
    return url.toString();
  }

  async function handleMagicLink(event: React.FormEvent) {
    event.preventDefault();
    setStatus("sending");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: callbackUrl() },
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
    } else {
      setStatus("sent");
    }
  }

  async function handleGoogle() {
    setIsGoogleLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: callbackUrl() },
    });
    if (error) {
      setIsGoogleLoading(false);
      setErrorMessage(error.message);
    }
    // On success the browser navigates away to Google, so no further state needed.
  }

  return (
    <div className="mx-auto flex min-h-[70vh] max-w-sm items-center px-4">
      <Card className="w-full">
        <CardHeader>
          <CardTitle>Sign in</CardTitle>
          <CardDescription>
            Vote, comment, and submit feature requests for Twofold.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {status === "sent" ? (
            <div className="flex flex-col items-center gap-3 py-6 text-center">
              <Mail className="h-8 w-8 text-muted-foreground" />
              <p className="text-sm">
                Check <strong>{email}</strong> for a sign-in link.
              </p>
            </div>
          ) : (
            <>
              <Button
                type="button"
                variant="outline"
                className="w-full"
                onClick={handleGoogle}
                disabled={isGoogleLoading}
              >
                {isGoogleLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <GoogleIcon />}
                Continue with Google
              </Button>

              <div className="relative text-center text-xs text-muted-foreground">
                <span className="bg-card relative z-10 px-2">or</span>
                <div className="absolute inset-x-0 top-1/2 border-t" />
              </div>

              <form onSubmit={handleMagicLink} className="space-y-3">
                <div className="space-y-1.5">
                  <Label htmlFor="email">Email</Label>
                  <Input
                    id="email"
                    type="email"
                    placeholder="you@example.com"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </div>
                <Button type="submit" className="w-full" disabled={status === "sending"}>
                  {status === "sending" && <Loader2 className="h-4 w-4 animate-spin" />}
                  Send magic link
                </Button>
              </form>

              {status === "error" && (
                <p className="text-sm text-destructive">{errorMessage}</p>
              )}
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.47c-.28 1.5-1.13 2.77-2.4 3.62v3.01h3.88c2.27-2.09 3.57-5.17 3.57-8.82z"
      />
      <path
        fill="#34A853"
        d="M12 24c3.24 0 5.96-1.07 7.95-2.91l-3.88-3.01c-1.08.72-2.45 1.15-4.07 1.15-3.13 0-5.78-2.11-6.73-4.95H1.27v3.11C3.25 21.3 7.31 24 12 24z"
      />
      <path
        fill="#FBBC05"
        d="M5.27 14.28c-.24-.72-.38-1.49-.38-2.28s.14-1.56.38-2.28V6.61H1.27A11.96 11.96 0 0 0 0 12c0 1.93.46 3.76 1.27 5.39l4-3.11z"
      />
      <path
        fill="#EA4335"
        d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.44-3.44C17.95 1.19 15.24 0 12 0 7.31 0 3.25 2.7 1.27 6.61l4 3.11C6.22 6.86 8.87 4.75 12 4.75z"
      />
    </svg>
  );
}
