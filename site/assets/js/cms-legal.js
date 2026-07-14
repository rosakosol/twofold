// Twofold — hydrates a legal page (privacy.html or terms.html) from Sanity, if
// published. `pageId` is passed in per-page via a small inline script (see the two
// legal pages) — "privacy" or "terms", matching the fixed legalPage-<id> document.

import { sanityFetch, portableTextToHtml, hydrateCms } from "/assets/js/cms.js";

const pageId = document.body.dataset.legalPage;

function formatDate(isoDate) {
  if (!isoDate) return null;
  const date = new Date(`${isoDate}T00:00:00`);
  if (Number.isNaN(date.getTime())) return isoDate;
  return date.toLocaleDateString("en-US", { day: "numeric", month: "long", year: "numeric" });
}

async function init() {
  if (!pageId) return;

  const page = await sanityFetch(`*[_id == $id][0]{title, lastUpdated, noticeText, body}`, {
    id: `legalPage-${pageId}`,
  });
  if (!page) return;

  const map = {};
  if (page.title) map["legal:title"] = page.title;
  const formatted = formatDate(page.lastUpdated);
  if (formatted) map["legal:lastUpdated"] = formatted;
  hydrateCms(map);

  const notice = document.getElementById("legal-notice");
  if (notice) {
    if (page.noticeText) {
      const span = notice.querySelector("[data-cms='legal:noticeText']");
      if (span) span.textContent = page.noticeText;
    } else {
      notice.hidden = true;
    }
  }

  const body = document.getElementById("legal-body");
  if (body && Array.isArray(page.body) && page.body.length) {
    body.innerHTML = portableTextToHtml(page.body);
  }
}

init();
