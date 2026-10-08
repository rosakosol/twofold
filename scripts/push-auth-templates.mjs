#!/usr/bin/env node
// Pushes the Auth email templates in supabase/config.toml ([auth.email.template.*]) to the hosted
// project, and nothing else.
//
// `supabase config push` would do this too, but it pushes the whole of config.toml, and that file
// is written for local dev: site_url is 127.0.0.1, custom SMTP is off, max_frequency is 1s.
// Pushing it would point every production auth email at localhost and drop the Zoho SMTP setup.
// So this goes through the Management API and PATCHes only the template subject and body fields.
//
// Anything above `<!DOCTYPE` in a template (the notes on why it is built the way it is) is
// stripped before sending, so recipients' "view source" doesn't carry them.
//
// Needs SUPABASE_ACCESS_TOKEN (a personal access token, supabase.com/dashboard/account/tokens).
// The project ref comes from `supabase link` (supabase/.temp/project-ref) or SUPABASE_PROJECT_REF.
//
// Usage: node scripts/push-auth-templates.mjs [--dry-run]
import { readFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dryRun = process.argv.includes("--dry-run");

const token = process.env.SUPABASE_ACCESS_TOKEN;
const refFile = resolve(root, "supabase/.temp/project-ref");
const ref =
  process.env.SUPABASE_PROJECT_REF ??
  (existsSync(refFile) ? readFileSync(refFile, "utf8").trim() : undefined);
if (!token) fail("SUPABASE_ACCESS_TOKEN is not set.");
if (!ref) fail("No project ref: run `supabase link`, or set SUPABASE_PROJECT_REF.");

// Only the shape config.toml uses for these sections: a header, then `key = "value"` lines.
const config = readFileSync(resolve(root, "supabase/config.toml"), "utf8").replace(/\r\n/g, "\n");
const templates = [];
for (const m of config.matchAll(/^\[auth\.email\.template\.(\w+)\]\s*\n((?:[ \t]*\w+[ \t]*=.*\n?)*)/gm)) {
  const fields = Object.fromEntries(
    [...m[2].matchAll(/^[ \t]*(\w+)[ \t]*=[ \t]*"(.*)"/gm)].map((f) => [f[1], f[2]]),
  );
  if (!fields.subject || !fields.content_path) fail(`[auth.email.template.${m[1]}] needs subject and content_path.`);
  const html = readFileSync(resolve(root, fields.content_path), "utf8");
  const start = html.search(/<!DOCTYPE/i);
  templates.push({ type: m[1], subject: fields.subject, content: start > 0 ? html.slice(start) : html });
}
if (templates.length === 0) fail("No [auth.email.template.*] sections in supabase/config.toml.");

const api = `https://api.supabase.com/v1/projects/${ref}/config/auth`;
const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

const current = await request("GET");
const patch = {};
for (const t of templates) {
  const subjectKey = `mailer_subjects_${t.type}`;
  const contentKey = `mailer_templates_${t.type}_content`;
  if (!(subjectKey in current)) fail(`The API has no ${subjectKey}; is "${t.type}" a template type?`);
  const changes = [];
  if (current[subjectKey] !== t.subject) {
    patch[subjectKey] = t.subject;
    changes.push(`subject "${current[subjectKey] ?? ""}" -> "${t.subject}"`);
  }
  if (current[contentKey] !== t.content) {
    patch[contentKey] = t.content;
    changes.push(`body ${current[contentKey]?.length ?? 0} -> ${t.content.length} chars`);
  }
  console.log(`${t.type}: ${changes.length ? changes.join(", ") : "unchanged"}`);
}

if (Object.keys(patch).length === 0) {
  console.log("Nothing to push.");
} else if (dryRun) {
  console.log("Dry run, nothing pushed.");
} else {
  await request("PATCH", patch);
  console.log(`Pushed to ${ref}.`);
}

async function request(method, body) {
  const res = await fetch(api, { method, headers, body: body && JSON.stringify(body) });
  if (!res.ok) fail(`${method} ${api}: ${res.status} ${await res.text()}`);
  return res.json();
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
