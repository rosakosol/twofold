import {defineField, defineType} from 'sanity'

// The 5 lean values are fixed on purpose (not a free-form number) — the site sums them
// to -2..+2 per question and recommends Premium if the total is positive, Plus
// otherwise. An editor can freely rewrite question/answer copy or change which option
// carries which lean, but can't produce an out-of-range or nonsensical score by doing
// so. See site/README.md "Content model" for the full scoring explanation.
export const QUIZ_LEANS = [
  {title: 'Strongly Plus', value: 'strong_plus'},
  {title: 'Leans Plus', value: 'plus'},
  {title: 'Neutral', value: 'neutral'},
  {title: 'Leans Premium', value: 'premium'},
  {title: 'Strongly Premium', value: 'strong_premium'},
]

export default defineType({
  name: 'quizQuestion',
  title: 'Quiz Question',
  type: 'document',
  fields: [
    defineField({name: 'question', title: 'Question', type: 'string', validation: (Rule) => Rule.required()}),
    defineField({
      name: 'order',
      title: 'Display order',
      type: 'number',
      description: 'Lower numbers show first.',
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'options',
      title: 'Answer options',
      type: 'array',
      validation: (Rule) => Rule.min(2).max(4).required(),
      of: [
        {
          type: 'object',
          name: 'quizOption',
          fields: [
            defineField({name: 'label', title: 'Answer text', type: 'string', validation: (Rule) => Rule.required()}),
            defineField({
              name: 'lean',
              title: 'Which plan does this answer lean toward?',
              type: 'string',
              options: {list: QUIZ_LEANS},
              validation: (Rule) => Rule.required(),
            }),
          ],
          preview: {select: {title: 'label', subtitle: 'lean'}},
        },
      ],
    }),
  ],
  orderings: [{title: 'Display order', name: 'orderAsc', by: [{field: 'order', direction: 'asc'}]}],
  preview: {
    select: {title: 'question', subtitle: 'order'},
    prepare: ({title, subtitle}) => ({title, subtitle: subtitle != null ? `#${subtitle}` : undefined}),
  },
})
