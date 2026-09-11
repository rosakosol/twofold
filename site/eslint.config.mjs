import coreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

// eslint-config-next 16 ships native flat configs, so these are spread directly. The
// previous setup routed them through @eslint/eslintrc's FlatCompat, which is for wrapping
// *legacy* eslintrc configs — running a flat config back through it makes the validator
// walk a self-referential plugin object and die on "Converting circular structure to JSON".
const eslintConfig = [
  ...coreWebVitals,
  ...typescript,
  {
    ignores: [
      "node_modules/**",
      ".next/**",
      "out/**",
      "build/**",
      "next-env.d.ts",
      // Git-ignored (.gitignore: site/design-system) and not ours to lint — it holds a
      // 1.1 MB vendored React build plus the sync tooling around it, which on its own
      // accounted for 1180 of the 1185 warnings and 14 of the 22 errors. Flat config
      // doesn't consult .gitignore, so it has to be named here.
      "design-system/**",
    ],
  },
];

export default eslintConfig;
