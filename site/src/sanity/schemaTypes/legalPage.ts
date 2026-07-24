import {defineField, defineType} from 'sanity'

export const LEGAL_PAGE_IDS = [
  {title: 'Privacy Policy', value: 'privacy'},
  {title: 'Terms of Use', value: 'terms'},
]

// Two documents, at fixed IDs legalPage-privacy / legalPage-terms (wired up in
// deskStructure.ts) — privacy.html / terms.html fetch by that fixed _id directly.
export default defineType({
  name: 'legalPage',
  title: 'Legal Page',
  type: 'document',
  fields: [
    defineField({
      name: 'pageId',
      title: 'Page',
      type: 'string',
      options: {list: LEGAL_PAGE_IDS},
      readOnly: true,
      description: 'Label only — which page this is is actually determined by the fixed document ID.',
    }),
    defineField({name: 'title', title: 'Page title', type: 'string', validation: (Rule) => Rule.required()}),
    defineField({name: 'lastUpdated', title: 'Last updated', type: 'date', validation: (Rule) => Rule.required()}),
    defineField({
      name: 'noticeText',
      title: 'Notice banner text (e.g. "Draft — pending legal review")',
      type: 'text',
      rows: 2,
      description: 'Leave empty to hide the notice banner entirely.',
    }),
    defineField({
      name: 'body',
      title: 'Body',
      type: 'array',
      of: [
        {
          type: 'block',
          styles: [
            {title: 'Normal', value: 'normal'},
            {title: 'Heading', value: 'h2'},
          ],
          lists: [{title: 'Bullet', value: 'bullet'}],
          marks: {
            decorators: [
              {title: 'Bold', value: 'strong'},
              {title: 'Italic', value: 'em'},
            ],
            annotations: [
              {
                name: 'link',
                type: 'object',
                title: 'Link',
                fields: [{name: 'href', type: 'url', title: 'URL', validation: (Rule) => Rule.required()}],
              },
            ],
          },
        },
      ],
      validation: (Rule) => Rule.required(),
    }),
  ],
  preview: {
    select: {title: 'title', subtitle: 'pageId'},
  },
})
