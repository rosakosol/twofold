import {defineField, defineType} from 'sanity'

export const QUIZ_RESULT_IDS = [
  {title: 'Result: Plus', value: 'plus'},
  {title: 'Result: Premium', value: 'premium'},
]

// Two documents, at fixed IDs quizResult-plus / quizResult-premium (wired up in
// deskStructure.ts) — pricing.html fetches both by those fixed _ids directly, same
// pattern as legalPage.
export default defineType({
  name: 'quizResult',
  title: 'Quiz Result',
  type: 'document',
  fields: [
    defineField({
      name: 'resultId',
      title: 'Result',
      type: 'string',
      options: {list: QUIZ_RESULT_IDS},
      readOnly: true,
      description: 'Label only — which result this is is actually determined by the fixed document ID.',
    }),
    defineField({name: 'title', title: 'Result headline', type: 'string', validation: (Rule) => Rule.required()}),
    defineField({name: 'description', title: 'Result description', type: 'text', rows: 3, validation: (Rule) => Rule.required()}),
    defineField({
      name: 'ctaLabel',
      title: 'Button label',
      type: 'string',
      description: 'e.g. "Get Twofold Plus"',
      validation: (Rule) => Rule.required(),
    }),
  ],
  preview: {
    select: {title: 'title', subtitle: 'resultId'},
  },
})
