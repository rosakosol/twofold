import {defineField, defineType} from 'sanity'
import {LivePriceInput} from '@/sanity/components/LivePriceInput'

export const PLAN_IDS = [
  {title: 'Plan: Plus', value: 'plus'},
  {title: 'Plan: Premium', value: 'premium'},
]

// Two documents, at fixed IDs plan-plus / plan-premium (wired up in deskStructure.ts) —
// the pricing page and the home pricing preview fetch both by those fixed _ids, same
// pattern as quizResult / legalPage.
//
// Copy is editable here; PRICES ARE NOT. /pricing reads what a visitor is actually charged
// straight off the RevenueCat offering and only falls back to the stored label, so an editable
// price field was a trap — typing "$7.99" moved the marketing copy and never the charge, and
// nothing surfaced the disagreement. The three price fields are readOnly and render the live
// figure instead (LivePriceInput); change a price in Stripe. Entitlement / package IDs live in
// code for the same reason, since they must match the iOS app and RevenueCat exactly.
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
      description: 'Highlights this plan’s card — heavier shadow, tinted border, and a solid rather than ghost button.',
      initialValue: false,
    }),
    defineField({
      name: 'monthlyPriceLabel',
      title: 'Monthly price',
      type: 'string',
      readOnly: true,
      components: {input: LivePriceInput},
      description: 'Set in Stripe. Shown here so you can see what visitors are charged.',
    }),
    defineField({
      name: 'yearlyPriceLabel',
      title: 'Yearly price (total)',
      type: 'string',
      readOnly: true,
      components: {input: LivePriceInput},
      description: 'The full yearly charge, from Stripe.',
    }),
    defineField({
      name: 'yearlyPerMonthLabel',
      title: 'Yearly price, per month',
      type: 'string',
      readOnly: true,
      components: {input: LivePriceInput},
      description: 'Derived from the yearly price, for the "/mo" figure on the card.',
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
