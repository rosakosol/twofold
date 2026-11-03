/**
 * An `ilike` pattern matching `search` anywhere, with LIKE's own wildcards taken literally.
 *
 * The admin search interpolated `%${search}%` raw, so "100%" or "snake_case" typed into it matched
 * far more than was typed. Postgres LIKE's default escape character is the backslash, so each of
 * `\`, `%` and `_` is prefixed with one. (PostgREST also reads `*` as `%`; a literal asterisk in a
 * request title is rare enough to leave.)
 */
export function containsPattern(search: string): string {
  return `%${search.replace(/[\\%_]/g, (ch) => `\\${ch}`)}%`;
}
