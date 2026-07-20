/** Turns a title into a URL slug. Not guaranteed unique on its own — callers should
 * append a short random suffix on a unique-constraint conflict (see useCreateFeature). */
export function slugify(title: string): string {
  return title
    .toLowerCase()
    .trim()
    .replace(/['"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

/** Short, URL-safe random suffix for disambiguating slug collisions. */
export function randomSlugSuffix(): string {
  return Math.random().toString(36).slice(2, 7);
}
