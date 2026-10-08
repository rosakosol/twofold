"use client";

import { Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { Loader2, MailCheck } from "lucide-react";
import { EmailPasswordForm, type EmailPasswordMode } from "@/components/auth/EmailPasswordForm";
import {
  PasswordResetPanel,
  passwordResetCopy,
  type PasswordResetStage,
} from "@/components/auth/PasswordResetPanel";

export default function SignInPage() {
  return (
    <Suspense>
      <SignInForm />
    </Suspense>
  );
}

/**
 * (board)'s own field and primary button, handed to the shared EmailPasswordForm so it wears
 * shadcn here and marketing.css on /pricing. Module scope, not inline: a component identity that
 * changed every render would remount the form and empty the fields on each keystroke.
 *
 * Taller than shadcn's default `h-8` on purpose — these fields sit directly under two 50px
 * brand-mandated capsules, and an 8px-tall input below them reads as a different form.
 */
function BoardField(props: React.ComponentProps<"input">) {
  return <Input {...props} className="h-10 rounded-full px-4" />;
}

function BoardSubmit(props: React.ComponentProps<"button">) {
  return <Button {...props} className="h-[50px] w-full rounded-full text-base" />;
}

/** The muted text link the shared reset panel gets back out through. */
function BoardBackLink(props: React.ComponentProps<"button">) {
  return (
    <button type="button" {...props} className="text-sm text-primary underline-offset-4 hover:underline" />
  );
}

function SignInForm() {
  const searchParams = useSearchParams();

  // Same rule as /auth/callback's own `next` handling, and for the same reason: this arrives from
  // the query string, so only a single-slash relative path is honoured. "//evil.com" is
  // protocol-relative and "https://evil.com" absolute, and either one handed to
  // `location.assign` below would be an open redirect fired by a successful sign-in — the worst
  // possible moment, since the victim has just proved they trust the page.
  const requestedNext = searchParams.get("next");
  const next = requestedNext && /^\/(?!\/)/.test(requestedNext) ? requestedNext : "/feedback";

  // Set by /auth/callback when it couldn't complete the exchange. Without rendering it,
  // a failed sign-in returns to this page looking untouched.
  const callbackError = searchParams.get("error");
  const callbackReason = searchParams.get("reason");

  // Sign in by default, the opposite of /pricing's default. Almost everyone who lands here was
  // sent by a control they pressed on the feedback board, so the question is which account they
  // already have; someone with none needs the switch below, not the front door.
  const [mode, setMode] = useState<EmailPasswordMode>("signin");
  // The stage lives here rather than inside the panel because it also picks the card's heading,
  // which sits in shadcn's CardHeader above it. The address and the in-flight flag are the panel's.
  const [resetStage, setResetStage] = useState<PasswordResetStage>("off");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
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

  // Apple and Google both land back on /auth/callback and exchange there, so the board ends
  // up with an ordinary Supabase session either way. Apple matters here because it's the
  // identity the iOS app and /pricing already use - signing in with it means the feedback
  // board, a web subscription and the app are all the same account row rather than three.
  async function handleOAuth(provider: "google" | "apple") {
    setOauthPending(provider);
    setErrorMessage(null);
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

  /**
   * Where an email/password sign-in ends up. The provider buttons don't come through here — they
   * leave for Apple or Google and return via /auth/callback, which does its own redirect.
   *
   * A full document load rather than `router.push(next)`, the same choice signOutAndGoHome makes
   * and for the mirror-image reason: Next's client router cache still holds the RSC payloads
   * rendered for a signed-out visitor, so a soft navigation can serve the destination back with no
   * session in it. One document load re-runs middleware, refreshes the cookie and renders the page
   * as the person who just signed in.
   */
  function handleSignedIn() {
    window.location.assign(next);
  }

  return (
    <div className="mx-auto flex min-h-[70vh] max-w-sm items-center px-4">
      <Card className="w-full">
        <CardHeader>
          <CardTitle>
            {resetStage !== "off"
              ? passwordResetCopy.title
              : mode === "create"
                ? "Create your account"
                : "Sign in"}
          </CardTitle>
          <CardDescription>
            {resetStage === "sent"
              ? passwordResetCopy.sent
              : resetStage === "form"
                ? passwordResetCopy.form
                : mode === "create"
                  ? "One Twofold account covers the feedback board, a web subscription and the app - it's what you'll sign in with when you download it."
                  : "Vote, comment, and submit feature requests for Twofold."}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {callbackError && (
            <div className="border-destructive/40 bg-destructive/10 rounded-md border p-3">
              <p className="text-destructive text-sm font-medium">
                That sign-in didn&apos;t complete.
              </p>
              {callbackReason && <p className="text-destructive/80 mt-1 text-xs">{callbackReason}</p>}
            </div>
          )}

          {resetStage !== "off" ? (
            /* Shared with /pricing's checkout step — see PasswordResetPanel on why the
               confirmation never says whether that address had an account. */
            <PasswordResetPanel
              stage={resetStage}
              onStageChange={setResetStage}
              onError={setErrorMessage}
              busyLabel={
                <>
                  <Loader2 className="size-4 animate-spin" />
                  Send reset link
                </>
              }
              sentNote={
                <div className="flex items-start gap-3 rounded-md border p-3">
                  <MailCheck className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
                  <p className="text-sm text-muted-foreground">
                    Open the link on any device &mdash; it doesn&apos;t have to be the one you asked
                    from. On an iPhone with Twofold installed it opens the app instead of the
                    browser.
                  </p>
                </div>
              }
              chrome={{
                form: "flex flex-col gap-3",
                Field: BoardField,
                Submit: BoardSubmit,
                BackLink: BoardBackLink,
              }}
            />
          ) : (
            <>
              <AppleGoogleSignInButtons pending={oauthPending} onPress={handleOAuth} />

              <div className="relative text-center text-xs text-muted-foreground">
                <span className="bg-card relative z-10 px-2">or</span>
                <div className="absolute inset-x-0 top-1/2 border-t" />
              </div>

              {/* The same component /pricing's checkout step uses, so the rules about what makes a
                  valid Twofold account live in one place — an account this page creates has to be
                  one the iOS app will accept, `first_name` metadata and all. Errors are reported up
                  rather than rendered by the form, because the paragraph below the branch also
                  carries OAuth and reset failures. */}
              <EmailPasswordForm
                mode={mode}
                onModeChange={setMode}
                onError={setErrorMessage}
                onSuccess={handleSignedIn}
                chrome={{ form: "flex flex-col gap-3", Field: BoardField, Submit: BoardSubmit }}
              />

              {/* The way out for somebody with no account. Without it this page is a door that only
                  opens for people who have already been through it. */}
              <p className="text-center text-sm">
                <button
                  type="button"
                  className="text-primary underline-offset-4 hover:underline"
                  onClick={() => {
                    setMode(mode === "create" ? "signin" : "create");
                    setErrorMessage(null);
                  }}
                >
                  {mode === "create"
                    ? "Already have a Twofold account? Sign in"
                    : "Need an account? Create one"}
                </button>
              </p>

              {/* Only on the sign-in side. Offering to reset a password to somebody in the middle
                  of choosing one is noise, and the app's own sign-in screen makes the same
                  distinction. */}
              {mode === "signin" && (
                <p className="text-center text-sm">
                  <button
                    type="button"
                    className="text-muted-foreground underline-offset-4 hover:underline"
                    onClick={() => {
                      setResetStage("form");
                      setErrorMessage(null);
                    }}
                  >
                    Forgot your password?
                  </button>
                </p>
              )}
            </>
          )}

          {/* Outside the branch on purpose: it carries OAuth failures, the shared form's errors and
              a failed reset request alike, and a reset is the path people reach already locked out
              — the one place an error must not be swallowed. */}
          {errorMessage && <p className="text-sm text-destructive">{errorMessage}</p>}
        </CardContent>
      </Card>
    </div>
  );
}

/**
 * The web twin of Twofold/Twofold/Features/Onboarding/AppleGoogleSignInButtons.swift — same 50px
 * height, same capsule, same 12px gap between them, same 0.6 opacity while a sign-in is in flight,
 * and the same two labels, so the app and the website ask for the same thing in the same words.
 *
 * Deliberately plain `<button>`s rather than shadcn's `Button`: every colour, the border and the
 * mark itself are Apple's and Google's brand requirements, so `buttonVariants` has nothing to
 * contribute here and inheriting its gradient or radius would make both buttons non-compliant.
 */
function AppleGoogleSignInButtons({
  pending,
  onPress,
}: {
  pending: "google" | "apple" | null;
  onPress: (provider: "google" | "apple") => void;
}) {
  const busy = pending !== null;

  return (
    <div className="flex flex-col gap-3">
      {/* Brand shapes and colours are Apple's and Google's; the scale is not. 44px with a 15px
          label rather than the app's 50px/19px: a phone button spans the screen, where these sit in
          a 384px card among 40px inputs, and matching the app's figures made them the loudest thing
          on the page. Google's own spec is smaller still (40px, 14px), so this stays inside it.

          Apple's adapts to the theme as the app's does, which flips it with
          `.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)`: black on light,
          white on dark, through the `dark:` variant, so it follows the header's toggle as well as
          the system. Google's stays its white "light" button in both, also as in the app. */}
      <button
        type="button"
        onClick={() => onPress("apple")}
        disabled={busy}
        className="flex h-11 w-full items-center justify-center gap-2 rounded-full bg-black text-[15px] font-medium text-white dark:bg-white dark:text-black disabled:pointer-events-none disabled:opacity-60"
      >
        {pending === "apple" ? (
          <Loader2 className="size-4 animate-spin" />
        ) : (
          <AppleIcon />
        )}
        Continue with Apple
      </button>

      <button
        type="button"
        onClick={() => onPress("google")}
        disabled={busy}
        className="flex h-11 w-full items-center justify-center gap-2.5 rounded-full border border-[#747775] bg-white text-[15px] font-medium text-[#1F1F1F] disabled:pointer-events-none disabled:opacity-60"
      >
        {pending === "google" ? (
          <Loader2 className="size-4 animate-spin" />
        ) : (
          <GoogleIcon />
        )}
        Sign in with Google
      </button>
    </div>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-[17px]" aria-hidden="true" fill="currentColor">
      <path d="M16.365 1.43c0 1.14-.42 2.2-1.12 3.02-.85.99-2.24 1.76-3.4 1.67a3.6 3.6 0 0 1-.03-.42c0-1.1.5-2.26 1.2-3.03.79-.88 2.14-1.55 3.28-1.6.04.12.07.25.07.36zM20.9 17.05c-.55 1.27-.82 1.84-1.53 2.96-.99 1.57-2.39 3.52-4.12 3.53-1.54.02-1.94-1-4.03-.99-2.1.01-2.53 1.01-4.07.99-1.73-.01-3.05-1.77-4.04-3.33C.32 15.84-.02 10.7 1.7 7.97c1.22-1.93 3.15-3.06 4.96-3.06 1.85 0 3 1.01 4.53 1.01 1.48 0 2.38-1.01 4.52-1.01 1.61 0 3.32.88 4.54 2.4-3.99 2.19-3.34 7.89.65 9.74z" />
    </svg>
  );
}

/** The official multicolour "G", at the 18×18 the app's own button draws the SDK's asset at. */
function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-4" aria-hidden="true">
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
