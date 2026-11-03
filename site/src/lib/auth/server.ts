import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

/**
 * The signed-in user for this request, looked up once.
 *
 * A layout and its page render concurrently and each called `auth.getUser()`, a round trip to
 * Supabase Auth, for the same answer. `cache` dedupes it for the length of one server request.
 */
export const getCurrentUser = cache(async () => {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  return data.user;
});
