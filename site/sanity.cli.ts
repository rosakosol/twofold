import path from "node:path";
import { defineCliConfig } from "sanity/cli";

/**
 * Sanity Studio as its own app on Sanity's hosting, separate from the website and its console
 * (see src/lib/studio.ts for why). From site/:
 *
 *   npx sanity dev      # http://localhost:3333
 *   npx sanity deploy   # builds and publishes; the first run asks for a host name
 *
 * The Studio reads the same .env.local as the site. Only the values it needs are compiled in, and
 * all three are already public: the Sanity project and dataset, and RevenueCat's web key, which the
 * plan editor uses to show live prices (src/sanity/components/LivePriceInput.tsx).
 */
try {
  process.loadEnvFile(path.join(process.cwd(), ".env.local"));
} catch {
  // No .env.local: rely on the environment (CI, or values set in the shell).
}

const PUBLIC_ENV = [
  "NEXT_PUBLIC_SANITY_PROJECT_ID",
  "NEXT_PUBLIC_SANITY_DATASET",
  "NEXT_PUBLIC_REVENUECAT_WEB_BILLING_API_KEY",
] as const;

export default defineCliConfig({
  api: {
    projectId: process.env.NEXT_PUBLIC_SANITY_PROJECT_ID,
    dataset: process.env.NEXT_PUBLIC_SANITY_DATASET,
  },
  // The first `sanity deploy` prints an app id. Put it here so later deploys go to the same Studio
  // without asking:
  // deployment: { appId: "..." },
  vite: (config) => ({
    ...config,
    // Not the site's postcss.config.mjs (Tailwind, in Next's string-plugin form, which Vite cannot
    // load). Studio brings its own styles and needs no PostCSS.
    css: { ...config.css, postcss: { plugins: [] } },
    resolve: {
      ...config.resolve,
      // The site's `@/` import alias (tsconfig.json), which the schema and components use.
      alias: { ...(config.resolve?.alias as Record<string, string> | undefined), "@": path.join(process.cwd(), "src") },
    },
    define: {
      ...config.define,
      ...Object.fromEntries(PUBLIC_ENV.map((name) => [`process.env.${name}`, JSON.stringify(process.env[name] ?? "")])),
    },
  }),
});
