// Twofold — renders the FAQ page's three category lists from Sanity, if published.
// Each category is replaced independently: if a category has no published items yet,
// that section keeps its hardcoded fallback list rather than going blank.

import { sanityFetch, escapeHtml } from "/assets/js/cms.js";

const CATEGORY_CONTAINERS = {
  "getting-started": "faq-getting-started",
  subscriptions: "faq-subscriptions",
  privacy: "faq-privacy",
};

function renderItem(item) {
  return `
    <details class="faq-item">
      <summary>${escapeHtml(item.question)}<svg class="icon icon-chevron"><use href="/assets/icons.svg#icon-chevron-down"/></svg></summary>
      <div class="faq-body">${escapeHtml(item.answer)}</div>
    </details>
  `;
}

async function init() {
  const items = await sanityFetch(`*[_type == "faqItem"] | order(order asc){question, answer, category}`);
  if (!items || !items.length) return;

  const byCategory = {};
  items.forEach((item) => {
    if (!item.question || !item.answer || !item.category) return;
    (byCategory[item.category] ??= []).push(item);
  });

  Object.entries(CATEGORY_CONTAINERS).forEach(([category, containerId]) => {
    const list = byCategory[category];
    if (!list || !list.length) return; // keep hardcoded fallback for this category
    const container = document.getElementById(containerId);
    if (container) container.innerHTML = list.map(renderItem).join("");
  });
}

init();
