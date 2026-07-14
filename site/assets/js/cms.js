// Twofold — minimal Sanity CMS client. Hand-rolled fetch (no @sanity/client) since the
// query API is just a GET request — one less dependency for something this small.
//
// Every call here is wrapped to fail soft: if the dataset is empty (nothing published
// yet), the project isn't set up, or the request errors (e.g. CORS not configured yet),
// callers get `null`/`[]` back and the page's existing hardcoded copy stays on screen.
// See site/README.md "CMS setup" for what has to be true for this to actually resolve.

import { SANITY_PROJECT_ID, SANITY_DATASET, SANITY_API_VERSION } from "/assets/js/config.js";

function isConfigured() {
  return Boolean(SANITY_PROJECT_ID) && !SANITY_PROJECT_ID.includes("TODO");
}

/** Runs a GROQ query against Sanity's read-only CDN API. Returns `null` on any failure. */
export async function sanityFetch(query, params = {}) {
  if (!isConfigured()) return null;

  const url = new URL(`https://${SANITY_PROJECT_ID}.apicdn.sanity.io/v${SANITY_API_VERSION}/data/query/${SANITY_DATASET}`);
  url.searchParams.set("query", query);
  Object.entries(params).forEach(([key, value]) => {
    url.searchParams.set(`$${key}`, JSON.stringify(value));
  });

  try {
    const response = await fetch(url.toString());
    if (!response.ok) return null;
    const data = await response.json();
    return data.result ?? null;
  } catch (err) {
    console.warn("[twofold] Sanity fetch failed", err);
    return null;
  }
}

/**
 * Applies a flat `{ "hero:eyebrow": "...", "feature:memories:title": "...", ... }` map
 * to every `[data-cms]` element on the page whose attribute value matches a key. Missing
 * or empty values are left untouched, so the page's hardcoded fallback copy stands.
 * Keys ending in `:headline` are treated as newline-separated lines and rendered as
 * `<br />`-joined HTML (see the hero headline field); everything else is plain text.
 */
export function hydrateCms(map) {
  document.querySelectorAll("[data-cms]").forEach((el) => {
    const key = el.dataset.cms;
    const value = map[key];
    if (value == null || value === "") return;

    if (key.endsWith(":headline")) {
      el.innerHTML = String(value)
        .split("\n")
        .map((line) => escapeHtml(line))
        .join("<br />");
    } else {
      el.textContent = value;
    }
  });
}

export function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str ?? "";
  return div.innerHTML;
}

/**
 * Minimal Portable Text → HTML renderer covering exactly what the legal-page schema
 * allows: normal/h2 blocks, bullet lists, strong/em marks, and link annotations. Not a
 * general-purpose renderer — if the schema grows richer block types, extend this.
 */
export function portableTextToHtml(blocks) {
  if (!Array.isArray(blocks)) return "";

  const html = [];
  let listBuffer = [];

  const flushList = () => {
    if (listBuffer.length) {
      html.push(`<ul>${listBuffer.join("")}</ul>`);
      listBuffer = [];
    }
  };

  for (const block of blocks) {
    if (block._type !== "block") continue;

    const inner = renderSpans(block.children ?? [], block.markDefs ?? []);

    if (block.listItem === "bullet") {
      listBuffer.push(`<li>${inner}</li>`);
      continue;
    }
    flushList();

    if (block.style === "h2") {
      html.push(`<h2>${inner}</h2>`);
    } else {
      html.push(`<p>${inner}</p>`);
    }
  }
  flushList();

  return html.join("\n");
}

function renderSpans(children, markDefs) {
  return children
    .map((span) => {
      let text = escapeHtml(span.text ?? "");
      const marks = span.marks ?? [];

      for (const mark of marks) {
        const def = markDefs.find((d) => d._key === mark);
        if (def?._type === "link" && def.href) {
          text = `<a class="text-link" href="${escapeHtml(def.href)}">${text}</a>`;
        } else if (mark === "strong") {
          text = `<strong>${text}</strong>`;
        } else if (mark === "em") {
          text = `<em>${text}</em>`;
        }
      }
      return text;
    })
    .join("");
}
