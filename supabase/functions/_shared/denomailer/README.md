# denomailer 1.6.0, patched

A copy of https://deno.land/x/denomailer@1.6.0 (MIT, see LICENSE), kept here because the bug below
is in upstream and every function that sends mail needs the fix. Only the runtime files are copied. Every change is marked
`TWOFOLD PATCH`, in `client/basic/client.ts` and `client/basic/connection.ts`:

- `#cleanup()` returns when the server has hung up. It sends `NOOP` after the server accepts a message,
  then loops until it reads a 250. A closed connection reads as null straight away and every time, so
  the loop never ended or yielded, and the edge runtime killed the function with `CPU Time exceeded`
  (HTTP 546). The mail had gone, but nothing after the send ran. `hangup.test.ts` covers this. If that
  test hangs rather than fails, this is why, and a timeout around `send()` cannot help: timers do not
  fire while the loop runs.
- `send()` no longer fails because that cleanup failed once the message is accepted, which would invite
  a resend of mail that had already gone.
- The `NOOP` write cannot become an unhandled rejection.
- The output pipe in `connection.ts` cannot reject unhandled when the connection closes, which the edge runtime treats as fatal.
- `Deno.startTls` gets a cast, because a local copy is type-checked and a remote one was not.

To check it: `deno test -A --no-check supabase/functions/_shared/denomailer/hangup.test.ts`