// Who may run the R2 purge: the cron, holding the service-role key, and nobody else.
//
// `verify_jwt` only proves the bearer is *a* valid token for this project — every signed-in user
// has one, and so does anybody holding the app's anon key. Without this, any of them could POST
// `{"dryRun": true}` and read back the whole deletion queue: keys naming the couple, memory and
// profile ids of everything recently deleted, which is the one list in the system that exists only
// because somebody asked for those things to be gone.
//
// Same rule as `send-streak-reminders` and `purge-dormant-accounts`, with one difference: an unset
// key refuses rather than comparing against the string "Bearer undefined".
export function isServiceRoleRequest(req: Request, serviceRoleKey: string | undefined): boolean {
  if (!serviceRoleKey) return false;
  return req.headers.get("Authorization") === `Bearer ${serviceRoleKey}`;
}
