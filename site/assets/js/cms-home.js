// Twofold — hydrates the home page hero + feature card copy from Sanity, if published.
// See site/studio for the schema and site/README.md "CMS setup" for what has to be
// true (project created, dataset public, CORS origin added) for this to resolve.

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
  const data = await sanityFetch(
    `{
      "hero": *[_id == "hero"][0]{eyebrow, headline, subtext, heroNote},
      "features": *[_type == "feature" && _id in $ids]{"key": _id, title, teaserDescription}
    }`,
    { ids: FEATURE_SLUGS.map((slug) => `feature-${slug}`) }
  );
  if (!data) return;

  const map = {};
  const hero = data.hero ?? {};
  if (hero.eyebrow) map["hero:eyebrow"] = hero.eyebrow;
  if (hero.headline) map["hero:headline"] = hero.headline;
  if (hero.subtext) map["hero:subtext"] = hero.subtext;
  if (hero.heroNote) map["hero:heroNote"] = hero.heroNote;

  (data.features ?? []).forEach((feature) => {
    const slug = feature.key?.replace(/^feature-/, "");
    if (!slug) return;
    if (feature.title) map[`feature:${slug}:title`] = feature.title;
    if (feature.teaserDescription) map[`feature:${slug}:teaserDescription`] = feature.teaserDescription;
  });

  hydrateCms(map);
}

init();
