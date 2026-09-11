"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
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
  const next = searchParams.get("next") ?? "/feedback";
  // Set by /auth/callback when it couldn't complete the exchange. Without rendering it,
  // a failed sign-in returns to this page looking untouched.
  const callbackError = searchParams.get("error");
  const callbackReason = searchParams.get("reason");

  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState("");
  // Which OAuth provider is mid-redirect, so only the button that was pressed shows a
  // spinner and neither can be pressed twice on a slow connection.
  const [oauthPending, setOauthPending] = useState<"google" | "apple" | null>(null);

  // Always the origin the user is actually on, never a build-time constant. PKCE stores the
  // code verifier in a cookie scoped to whichever origin started the flow, so sending the
  // callback anywhere else guarantees "code verifier not found in storage" — which is what
  // NEXT_PUBLIC_SITE_URL did here, and what Supabase's own Site URL fallback does whenever
  // this origin is missing from the project's Redirect URLs allow-list.
  function callbackUrl() {
    const url = new URL("/auth/callback", window.location.origin);
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

  // Apple and Google both land back on /auth/callback and exchange there, so the board ends
  // up with an ordinary Supabase session either way. Apple matters here because it's the
  // identity the iOS app and /pricing already use - signing in with it means the feedback
  // board, a web subscription and the app are all the same account row rather than three.
  async function handleOAuth(provider: "google" | "apple") {
    setOauthPending(provider);
    setErrorMessage("");
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider,
      options: { redirectTo: callbackUrl() },
    });
    if (error) {
      setOauthPending(null);
      setErrorMessage(error.message);
    }
    // On success the browser navigates away to the provider, so no further state needed.
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
              {callbackError && (
                <div className="border-destructive/40 bg-destructive/10 rounded-md border p-3">
                  <p className="text-destructive text-sm font-medium">
                    That sign-in didn&apos;t complete.
                  </p>
                  {callbackReason && (
                    <p className="text-destructive/80 mt-1 text-xs">{callbackReason}</p>
                  )}
                </div>
              )}

              <Button
                type="button"
                variant="outline"
                className="w-full"
                onClick={() => handleOAuth("apple")}
                disabled={oauthPending !== null}
              >
                {oauthPending === "apple" ? <Loader2 className="h-4 w-4 animate-spin" /> : <AppleIcon />}
                Continue with Apple
              </Button>

              <Button
                type="button"
                variant="outline"
                className="w-full"
                onClick={() => handleOAuth("google")}
                disabled={oauthPending !== null}
              >
                {oauthPending === "google" ? <Loader2 className="h-4 w-4 animate-spin" /> : <GoogleIcon />}
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
                    placeholder="yourname@email.com"
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

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4" aria-hidden="true" fill="currentColor">
      <path d="M16.365 1.43c0 1.14-.42 2.2-1.12 3.02-.85.99-2.24 1.76-3.4 1.67a3.6 3.6 0 0 1-.03-.42c0-1.1.5-2.26 1.2-3.03.79-.88 2.14-1.55 3.28-1.6.04.12.07.25.07.36zM20.9 17.05c-.55 1.27-.82 1.84-1.53 2.96-.99 1.57-2.39 3.52-4.12 3.53-1.54.02-1.94-1-4.03-.99-2.1.01-2.53 1.01-4.07.99-1.73-.01-3.05-1.77-4.04-3.33C.32 15.84-.02 10.7 1.7 7.97c1.22-1.93 3.15-3.06 4.96-3.06 1.85 0 3 1.01 4.53 1.01 1.48 0 2.38-1.01 4.52-1.01 1.61 0 3.32.88 4.54 2.4-3.99 2.19-3.34 7.89.65 9.74z" />
    </svg>
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
