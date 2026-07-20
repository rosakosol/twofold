// Mirrors next.config.ts's basePath — Next.js auto-prefixes framework routing (Link,
// router.push, the public/ folder) but NOT manually-constructed URL strings (raw <img
// src>, the auth callback's emailRedirectTo). Single source of truth for those cases.
export const BASE_PATH = "/feedback";
