import {defineField, defineType} from 'sanity'

export const FAQ_CATEGORIES = [
  {title: 'Getting started', value: 'getting-started'},
  {title: 'Subscriptions & billing', value: 'subscriptions'},
  {title: 'Privacy & data', value: 'privacy'},
]

// Free-form list — unlike features/hero/legal pages, editors can add or remove FAQ
// items freely; faq.html renders whatever exists per category, grouped and ordered.
export default defineType({
  name: 'faqItem',
  title: 'FAQ Item',
  type: 'document',
  fields: [
    defineField({name: 'question', title: 'Question', type: 'string', validation: (Rule) => Rule.required()}),
    defineField({name: 'answer', title: 'Answer', type: 'text', rows: 4, validation: (Rule) => Rule.required()}),
    defineField({
      name: 'category',
      title: 'Category',
      type: 'string',
      options: {list: FAQ_CATEGORIES},
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'order',
      title: 'Display order within category',
      type: 'number',
      description: 'Lower numbers show first.',
    }),
  ],
  orderings: [{title: 'Display order', name: 'orderAsc', by: [{field: 'order', direction: 'asc'}]}],
  preview: {
    select: {title: 'question', subtitle: 'category'},
  },
})
