import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// Unit tests for the site's own logic (lib/, route handlers). Kept out of the Next build: Next only
// compiles what the app imports, and nothing imports *.test.ts.
export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
