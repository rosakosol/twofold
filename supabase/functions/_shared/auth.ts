// Who is calling: the two questions nearly every function here asks first.
//
// `isServiceRoleRequest` is for the cron entrypoints and the trigger-invoked functions. Their
// `verify_jwt` only proves the bearer is *a* valid token for this project, and every signed-in
// user has one, so each handler also checks that the bearer is the service-role key itself.
//
// `userSession` is for the functions the app calls on a person's behalf: a client that runs as the
// caller (so RLS applies), and the user that token belongs to, or null when there isn't one.
// Each caller still writes its own 401, because the bodies differ and the app reads some of them.

import { createClient, type SupabaseClient, type User } from "jsr:@supabase/supabase-js@2";

/// Constant-time string comparison. Hashing both sides first is what lets this handle unequal
/// lengths without an early return: SHA-256 digests are always 32 bytes, so the loop runs the same
/// number of iterations no matter how wrong the candidate is — including how wrong its length is —
/// and the digest of a wrong secret reveals nothing about the right one.
export async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [aHash, bHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const aBytes = new Uint8Array(aHash);
  const bBytes = new Uint8Array(bHash);
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) diff |= aBytes[i] ^ bBytes[i];
  return diff === 0;
}

/// True only when the request carries `Authorization: Bearer <service-role key>`. An unset or empty
/// key refuses everyone, rather than letting in a caller who sends the literal `Bearer undefined`.
export async function isServiceRoleRequest(
  req: Request,
  serviceRoleKey: string | undefined = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
): Promise<boolean> {
  if (!serviceRoleKey) return false;
  const presented = req.headers.get("Authorization") ?? "";
  return await timingSafeEqual(presented, `Bearer ${serviceRoleKey}`);
}

/// A client that acts as whoever sent the request: the anon key plus the caller's own JWT.
export function userClientFor(req: Request, projectUrl = Deno.env.get("SUPABASE_URL")!): SupabaseClient {
  return createClient(
    projectUrl,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
}

/// The caller's client and user, or `user: null` when the request has no valid session.
export async function userSession(
  req: Request,
  projectUrl?: string,
): Promise<{ userClient: SupabaseClient; user: User | null }> {
  const userClient = userClientFor(req, projectUrl);
  const { data: { user } } = await userClient.auth.getUser();
  return { userClient, user };
}
