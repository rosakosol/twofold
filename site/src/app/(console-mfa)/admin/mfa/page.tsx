import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { getConsoleAccess } from "@/lib/auth/consoleAccess";
import { consoleGate } from "@/lib/auth/consoleGate";
import { safeNext } from "@/lib/auth/safeNext";
import { MfaChallenge, MfaEnrolCard } from "@/components/console/MfaForms";

export const metadata: Metadata = { title: "Sign-in code" };

export const dynamic = "force-dynamic";

/**
 * The console's second step: a code if the admin has a factor, enrolment if they don't. Everything
 * it needs works at aal1. `consoleGate` is the same decision the (console) layout makes, so the two
 * cannot send somebody back and forth.
 */
export default async function ConsoleMfaPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next: rawNext } = await searchParams;
  // Only the path is used, and the base is only there to resolve it against.
  const next = safeNext(rawNext, "https://www.twofoldapp.com.au", "/admin");

  const gate = consoleGate(await getConsoleAccess());
  if (gate === "not-admin") redirect("/feedback");
  if (gate === "open") redirect(next);

  return (
    <div className="mfa-door">
      {gate === "challenge" ? (
        <MfaChallenge next={next} />
      ) : (
        <MfaEnrolCard next={next} required={gate === "enrol"} />
      )}
    </div>
  );
}
