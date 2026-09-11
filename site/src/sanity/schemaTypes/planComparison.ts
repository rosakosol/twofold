import {defineField, defineType} from 'sanity'

// One document at the fixed id `planComparison` (wired up in deskStructure.ts), rendered on
// /pricing underneath the plan cards. Singleton rather than a free-form list because there is
// exactly one table — the rows inside it are what editors add to and reorder.
//
// The cards above it show each plan's headline selling points (PLANS.*.features, editable on
// the `plan` documents). This is the row-by-row version for someone already deciding between
// the two, so the two lists are allowed to differ: the cards sell, the table compares.
export default defineType({
  name: 'planComparison',
  title: 'Plan Comparison Table',
  type: 'document',
  fields: [
    defineField({
      name: 'heading',
      title: 'Heading',
      type: 'string',
      description: 'Shown above the table. Leave empty to fall back to the copy in code.',
    }),
    defineField({
      name: 'intro',
      title: 'Intro line',
      type: 'text',
      rows: 2,
      description: 'Optional sentence under the heading.',
    }),
    defineField({
      name: 'rows',
      title: 'Rows',
      type: 'array',
      validation: (Rule) => Rule.min(1),
      of: [
        {
          type: 'object',
          name: 'comparisonRow',
          fields: [
            defineField({
              name: 'label',
              title: 'Feature',
              type: 'string',
              validation: (Rule) => Rule.required(),
            }),
            defineField({
              name: 'plus',
              title: 'Twofold Plus',
              type: 'string',
              description:
                'What this plan gets — e.g. "5 / month". Type exactly "Yes" for a tick. Leave empty for a dash (not included).',
            }),
            defineField({
              name: 'premium',
              title: 'Twofold Premium',
              type: 'string',
              description:
                'What this plan gets — e.g. "20 / month". Type exactly "Yes" for a tick. Leave empty for a dash (not included).',
            }),
          ],
          preview: {
            select: {title: 'label', plus: 'plus', premium: 'premium'},
            prepare: ({title, plus, premium}) => ({
              title,
              subtitle: `Plus: ${plus || '—'}   ·   Premium: ${premium || '—'}`,
            }),
          },
        },
      ],
    }),
  ],
  preview: {
    select: {rows: 'rows'},
    prepare: ({rows}) => ({
      title: 'Plan Comparison Table',
      subtitle: `${rows?.length ?? 0} row${rows?.length === 1 ? '' : 's'}`,
    }),
  },
})
