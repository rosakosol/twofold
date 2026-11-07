/**
 * One plain address, for anything we send mail to. Refuses what a mail library reads as something
 * else: `x<victim@example.com>`, `a,victim@example.com` and `(c)victim@example.com` all deliver to
 * the victim while looking like a new address to a per-address rate limit. Stricter than the
 * database's own check (20261114003100), which allows brackets and colons.
 */
const PART = '[^\\s\\u0000-\\u001f\\u007f<>()\\[\\]:;,"\\\\@]+';
const ADDRESS = new RegExp(`^${PART}@${PART}\\.${PART}$`);

export function isPlainEmailAddress(value: string): boolean {
  return ADDRESS.test(value);
}
