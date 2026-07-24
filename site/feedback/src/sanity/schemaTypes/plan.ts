import {defineField, defineType} from 'sanity'

export const PLAN_IDS = [
  {title: 'Plan: Plus', value: 'plus'},
  {title: 'Plan: Premium', value: 'premium'},
]

// Two documents, at fixed IDs plan-plus / plan-premium (wired up in deskStructure.ts) —
// the pricing page and the home pricing preview fetch both by those fixed _ids, same
// pattern as quizResult / legalPage.
//
// IMPORTANT: this is DISPLAY copy only. The price LABELS here (e.g. "$9.99") are what
// visitors see, but what they're actually charged comes from RevenueCat via the
// packageId wiring in src/lib/marketing/config.ts — editing a label here does NOT change
// the real charge, and the two must be kept in sync by hand. Entitlement / package IDs
// deliberately live in code (they must match the iOS app + RevenueCat exactly) and are
// not editable here. If a field is left blank, the site falls back to the code default.
export default defineType({
  name: 'plan',
  title: 'Pricing Plan',
  type: 'document',
  fields: [
    defineField({
      name: 'planId',
      title: 'Plan',
      type: 'string',
      options: {list: PLAN_IDS},
      readOnly: true,
      description: 'Label only — which plan this is is determined by the fixed document ID.',
    }),
    defineField({name: 'name', title: 'Plan name', type: 'string', description: 'e.g. "Twofold Plus"'}),
    defineField({
      name: 'tagline',
      title: 'Tagline',
      type: 'string',
      description: 'Short line under the plan name.',
    }),
    defineField({
      name: 'featured',
      title: 'Feature this plan',
      type: 'boolean',
      description: 'Shows the "Most popular" badge and the highlighted card style.',
      initialValue: false,
    }),
    defineField({
      name: 'monthlyPriceLabel',
      title: 'Monthly price label',
      type: 'string',
      description: 'Shown on the Monthly toggle. Display only — e.g. "$9.99". Must match RevenueCat.',
    }),
    defineField({
      name: 'yearlyPriceLabel',
      title: 'Yearly total price label',
      type: 'string',
      description: 'The full yearly charge — e.g. "$59.99". Display only; must match RevenueCat.',
    }),
    defineField({
      name: 'yearlyPerMonthLabel',
      title: 'Yearly price, per month',
      type: 'string',
      description: 'The yearly price divided by 12, for the "/mo" figure — e.g. "$5.00".',
    }),
    defineField({
      name: 'ctaLabel',
      title: 'Button label',
      type: 'string',
      description: 'e.g. "Get Plus". Defaults to "Get Plus"/"Get Premium" if left blank.',
    }),
    defineField({
      name: 'features',
      title: 'Feature bullets',
      type: 'array',
      of: [{type: 'string'}],
      description: 'The checklist shown on the card, in order.',
    }),
  ],
  preview: {
    select: {title: 'name', subtitle: 'planId'},
    prepare: ({title, subtitle}) => ({title: title || 'Pricing Plan', subtitle}),
  },
})
