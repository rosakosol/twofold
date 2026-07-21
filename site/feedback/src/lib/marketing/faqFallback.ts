import type { FaqItemDoc } from "@/lib/marketing/sanity";

// Ported verbatim from the old static faq.html — shown per-category only when Sanity
// has no published items for that category, same "never blank the page" fail-soft
// pattern the old cms-faq.js used.
export const FAQ_FALLBACK: FaqItemDoc[] = [
  {
    category: "getting-started",
    order: 1,
    question: "What is Twofold?",
    answer:
      "Twofold is a native iOS app built for long-distance couples. It turns your relationship into a living map — track each other's flights in real time, watch the distance between you close, and save memories to the places they happened, all on a shared 3D globe.",
  },
  {
    category: "getting-started",
    order: 2,
    question: "What platforms is Twofold available on?",
    answer:
      "Twofold is available now on iOS. We're building the Android version next — join the waitlist and we'll email you the moment it's ready.",
  },
  {
    category: "getting-started",
    order: 3,
    question: "How do I connect with my partner?",
    answer:
      "During onboarding you'll get a personal invite link. Send it to your partner and once they accept, your accounts are connected — trips, flights, memories, and games become shared from that point on.",
  },
  {
    category: "subscriptions",
    order: 1,
    question: "What's the difference between Plus and Premium?",
    answer:
      "Plus covers everything most couples need — unlimited trips and memories, up to 5 tracked flights a month, and 500+ questions and games. Premium adds more flight tracking, 2000+ questions and games, the interactive 3D globe, premium widgets, and the Relationship Record PDF export. See the full comparison on the pricing page.",
  },
  {
    category: "subscriptions",
    order: 2,
    question: "Can I subscribe on the web instead of in the app?",
    answer:
      "Yes. You can subscribe right from our pricing page using Sign in with Apple — it unlocks your account the same way an in-app purchase does. Open the app afterward and sign in with the same Apple ID to see it active.",
  },
  {
    category: "subscriptions",
    order: 3,
    question: "How do I cancel or manage my subscription?",
    answer:
      "If you subscribed in the app, manage or cancel it from your device's Settings → Apple ID → Subscriptions. If you subscribed on the web, manage it from your account on the pricing page, or email hello@twofoldapp.com.au and we'll sort it out. Either way, you keep access until the end of the period you've already paid for.",
  },
  {
    category: "subscriptions",
    order: 4,
    question: "Does one subscription cover both partners?",
    answer:
      "Yes — once you're connected, either partner's active Plus or Premium subscription unlocks the full experience for both of you. Only one of you needs to subscribe.",
  },
  {
    category: "subscriptions",
    order: 5,
    question: "Is my payment secure?",
    answer:
      "Web purchases are processed by Stripe via RevenueCat — Twofold never sees or stores your card details. In-app purchases go through Apple's App Store billing.",
  },
  {
    category: "privacy",
    order: 1,
    question: "Who can see my trips and location?",
    answer:
      "Only the partner you're connected to. Twofold isn't a public or social app, and your travel information is never shared beyond your relationship. See our Privacy Policy for details.",
  },
  {
    category: "privacy",
    order: 2,
    question: "Does Twofold track my location continuously?",
    answer:
      "No. Twofold isn't a continuous live-location tracker — it's based on the trips and flights you intentionally share, plus your home city.",
  },
  {
    category: "privacy",
    order: 3,
    question: "What happens to shared data if we disconnect?",
    answer:
      "Removing a partner archives your shared data rather than deleting it immediately, so either of you can permanently delete it afterward from Settings.",
  },
];

export const FAQ_CATEGORY_LABELS: Record<FaqItemDoc["category"], string> = {
  "getting-started": "Getting started",
  subscriptions: "Subscriptions & billing",
  privacy: "Privacy & data",
};
