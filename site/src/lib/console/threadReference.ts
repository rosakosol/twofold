/**
 * The short reference a support conversation goes by: the first eight characters of its
 * support_threads id, upper-cased. "4F1C09AB" for 4f1c09ab-….
 *
 * The website's receipt and internal alert quote it as "#4F1C09AB", and the console prints the same
 * thing in the conversation's header. That is the whole point: it used to be six random characters
 * made up per email, which nobody in the console could look up (SITE-18).
 *
 * It is not the thread's reply-to token. That one routes mail into the thread, so it is never shown.
 */
export function threadReference(threadId: string): string {
  return threadId.replace(/-/g, "").slice(0, 8).toUpperCase();
}
