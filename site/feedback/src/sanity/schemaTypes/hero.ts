import {defineField, defineType} from 'sanity'

export default defineType({
  name: 'hero',
  title: 'Home Hero',
  type: 'document',
  fields: [
    defineField({
      name: 'eyebrow',
      title: 'Eyebrow (small label above the headline)',
      type: 'string',
      initialValue: 'Built for long-distance couples',
    }),
    defineField({
      name: 'headline',
      title: 'Headline',
      type: 'text',
      rows: 2,
      description: 'Rendered as the big H1 on the home page. A line break here becomes a line break there.',
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'subtext',
      title: 'Subtext',
      type: 'text',
      rows: 3,
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'heroNote',
      title: 'Small trust note (under the buttons)',
      type: 'string',
    }),
  ],
  preview: {
    prepare: () => ({title: 'Home Hero'}),
  },
})
