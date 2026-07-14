// Twofold — hydrates the features page's per-feature copy from Sanity, if published.

import { sanityFetch, hydrateCms } from "/assets/js/cms.js";

const FEATURE_SLUGS = [
  "relationship-globe",
  "live-flight-tracking",
  "memories",
  "couple-games",
  "widgets-live-activities",
  "relationship-record",
];

async function init() {
  const features = await sanityFetch(
    `*[_type == "feature" && _id in $ids]{"key": _id, title, detailDescription, bullets}`,
    { ids: FEATURE_SLUGS.map((slug) => `feature-${slug}`) }
  );
  if (!features) return;

  const map = {};
  features.forEach((feature) => {
    const slug = feature.key?.replace(/^feature-/, "");
    if (!slug) return;
    if (feature.title) map[`feature:${slug}:title`] = feature.title;
    if (feature.detailDescription) map[`feature:${slug}:detailDescription`] = feature.detailDescription;
    (feature.bullets ?? []).forEach((bullet, i) => {
      if (bullet) map[`feature:${slug}:bullets:${i}`] = bullet;
    });
  });

  hydrateCms(map);
}

init();
