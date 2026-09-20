// Mints presigned R2 URLs, once the caller has been shown to be allowed one.
//
// Supabase Storage answered "may this person read this object?" on every request, out of the RLS
// policies attached to `storage.objects`. R2 does not: it authorises by signature alone, and a
// presigned URL works for anyone holding it until it expires. So the question has to be asked
// here, before the URL exists.
//
// The answer is not computed here. `public.can_access_storage_object` (20261030000000) holds the
// rules, transcribed from the policies they replace, and `storage_object_access_test.sql` pins
// every branch. This file's job is to parse a request, ask that one question, and sign — so that
// there is exactly one copy of the rules and it is the tested one.
//
// Called with the caller's own `Authorization` header (verify_jwt = true), because the function
// reads `auth.uid()` through the user-scoped client. A service-role client here would make every
// check pass, which is the entire risk this file is built around.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { presign, r2ConfigFromEnv } from "../_shared/r2.ts";
import { enforceRateLimit } from "../_shared/rate-limit.ts";

/// The four private kinds, and where each lives in the bucket.
///
/// The database stores paths without a bucket prefix — `memory_photos.photo_path` is still
/// `{coupleID}/{memoryID}/{uuid}.jpg`, exactly as Supabase Storage held it. The prefix is added
/// here, which is what lets the migration be a copy of objects and not a rewrite of every row.
const PREFIX: Record<string, string> = {
  "avatar": "avatars",
  "drawing-pad": "drawing-pads",
  "memory-photo": "memory-photos",
  "flight-document": "flight-documents",
};

/// How long each kind's URL lives.
///
/// An hour for everything the app mints per load and throws away. Twelve for drawing pads, the one
/// URL that gets written to disk: `WidgetSnapshot` persists it into the app group so the widget —
/// which has no Supabase session and cannot sign anything — can still fetch. Keep this in step with
/// `BackendService.drawingPadURLLifetimeSeconds`, which is the same number on the client side.
const EXPIRES_IN: Record<string, number> = {
  "avatar": 60 * 60,
  "drawing-pad": 60 * 60 * 12,
  "memory-photo": 60 * 60,
  "flight-document": 60 * 60,
};

/// A write URL is short-lived on purpose. It is handed out the moment before an upload starts and
/// is never stored, so minutes is generous; an hour would just widen the window in which a
/// credential that can *write* to the couple's storage is floating around.
const WRITE_EXPIRES_IN = 5 * 60;

/// Generous, because this is on the path of every image the app draws — a memories grid is one
/// call, but a session is plenty of them, and a limit that bites would show up as missing photos
/// rather than as an error anyone would report. It is here to stop a client stuck in a loop, not
/// to ration normal use.
const RATE_LIMIT = { bucket: "storage-url", limit: 600, window: "1 hour" };

/// One request should cover a screen, not a library. A memories grid asks for what it is about to
/// draw; anything past this is a client doing something the app does not do.
const MAX_PATHS = 100;

interface Input {
  kind?: unknown;
  op?: unknown;
  paths?: unknown;
  contentType?: unknown;
}

function bad(message: string, status = 400): Response {
  return Response.json({ error: message }, { status });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return bad("POST only", 405);

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (error) {
    // Misconfiguration, not the caller's fault — and worth being loud about, because the
    // alternative is every image in the app quietly failing to load.
    console.error("[storage-url]", (error as Error).message);
    return bad("Storage is not configured", 500);
  }

  let input: Input;
  try {
    input = await req.json();
  } catch {
    return bad("Body must be JSON");
  }

  const kind = typeof input.kind === "string" ? input.kind : "";
  const op = typeof input.op === "string" ? input.op : "read";
  if (!PREFIX[kind]) return bad("Unknown 'kind'");
  if (op !== "read" && op !== "write" && op !== "delete") return bad("Unknown 'op'");

  const paths = Array.isArray(input.paths) ? input.paths : [];
  if (paths.length === 0) return bad("'paths' must be a non-empty array");
  if (paths.length > MAX_PATHS) return bad(`'paths' is limited to ${MAX_PATHS} per request`);
  if (!paths.every((p) => typeof p === "string" && p.length > 0)) {
    return bad("'paths' must be non-empty strings");
  }

  const contentType = typeof input.contentType === "string" ? input.contentType : undefined;
  if (op === "write" && !contentType) return bad("'contentType' is required to write");

  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return bad("Not authenticated", 401);

  const limited = await enforceRateLimit(userClient, RATE_LIMIT);
  if (limited) return limited;

  // Asked per path rather than once for the batch: paths in one request can belong to different
  // couples (a memories grid after a reconnection, say), and answering the batch on the strength of
  // the first path would hand out URLs for the rest unchecked.
  const decisions = await Promise.all(
    (paths as string[]).map(async (path) => {
      const { data, error } = await userClient.rpc("can_access_storage_object", {
        p_kind: kind,
        p_path: path,
        p_op: op,
      });
      if (error) {
        console.error("[storage-url] access check failed:", error.message);
        return { path, allowed: false };
      }
      return { path, allowed: data === true };
    }),
  );

  const refused = decisions.filter((d) => !d.allowed);
  if (refused.length > 0) {
    // All or nothing, and without naming which path was refused. Partial success would have the
    // app render some images and silently drop others with no way to tell a permissions problem
    // from a network one; naming the path would turn this endpoint into a way to ask whether a
    // given object exists and belongs to someone.
    return bad("Not allowed", 403);
  }

  const expiresIn = op === "read" ? EXPIRES_IN[kind] : WRITE_EXPIRES_IN;
  const method = op === "read" ? "GET" : op === "write" ? "PUT" : "DELETE";

  const urls: Record<string, string> = {};
  for (const path of paths as string[]) {
    urls[path] = await presign(config, `${PREFIX[kind]}/${path}`, {
      method,
      expiresIn,
      contentType: op === "write" ? contentType : undefined,
    });
  }

  return Response.json({ urls, expiresIn });
});
