import { assert, assertEquals } from "jsr:@std/assert@1";
import { isServiceRoleRequest } from "./auth.ts";

const KEY = "service-role-key-for-tests";

function withAuth(value: string | null): Request {
  const headers = new Headers();
  if (value !== null) headers.set("Authorization", value);
  return new Request("http://localhost/functions/v1/purge-r2-objects", { method: "POST", headers });
}

Deno.test("the service-role key is let in", () => {
  assert(isServiceRoleRequest(withAuth(`Bearer ${KEY}`), KEY));
});

Deno.test("a signed-in user's token, or the anon key, is not", () => {
  assertEquals(isServiceRoleRequest(withAuth("Bearer eyJ.user.token"), KEY), false);
  assertEquals(isServiceRoleRequest(withAuth(null), KEY), false);
  assertEquals(isServiceRoleRequest(withAuth(KEY), KEY), false);
});

Deno.test("an unset key refuses everyone, including a caller who sends 'Bearer undefined'", () => {
  assertEquals(isServiceRoleRequest(withAuth("Bearer undefined"), undefined), false);
  assertEquals(isServiceRoleRequest(withAuth("Bearer "), ""), false);
});

// The guard is only worth anything if it runs before the queue is read. Checked on the source, the
// same way storage-url pins MAX_PATHS, because index.ts serves on import and cannot be called here.
Deno.test("index.ts checks the caller before it reads the queue", async () => {
  const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const guard = source.indexOf("isServiceRoleRequest(req");
  const read = source.indexOf('.from("pending_object_deletions")');
  assert(guard !== -1, "index.ts no longer calls isServiceRoleRequest");
  assert(read !== -1, "index.ts no longer reads pending_object_deletions");
  assert(guard < read, "the queue is read before the caller is checked");
});
