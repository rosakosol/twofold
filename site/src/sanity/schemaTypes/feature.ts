import {defineField, defineType} from 'sanity'

export const FEATURE_ICONS = [
  {title: 'Globe', value: 'globe'},
  {title: 'Plane', value: 'plane'},
  {title: 'Pin', value: 'pin'},
  {title: 'Gamepad', value: 'gamepad'},
  {title: 'Grid', value: 'grid'},
  {title: 'File download', value: 'file-download'},
]

export const FEATURE_TONES = [
  {title: 'Sky blue', value: 'sky'},
  {title: 'Leaf green', value: 'green'},
  {title: 'Heart red', value: 'red'},
  {title: 'Ink', value: 'ink'},
]

// One document per feature card, at a fixed document ID (feature-<key>, wired up via
// deskStructure.ts) — there are exactly 6 slots in the site's HTML (home page cards +
// features.html detail sections), so this is copy-only, not a free-form list editors
// add to or remove from. See site/README.md "Content model".
export default defineType({
  name: 'feature',
  title: 'Feature',
  type: 'document',
  fields: [
    defineField({name: 'title', title: 'Title', type: 'string', validation: (Rule) => Rule.required()}),
    defineField({
      name: 'teaserDescription',
      title: 'Short description (home page card)',
      type: 'text',
      rows: 2,
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'detailDescription',
      title: 'Long description (features page)',
      type: 'text',
      rows: 4,
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'bullets',
      title: 'Feature bullets (features page — exactly 3 are shown)',
      type: 'array',
      of: [{type: 'string'}],
      validation: (Rule) => Rule.max(3).min(3),
    }),
    defineField({
      name: 'icon',
      title: 'Icon',
      type: 'string',
      options: {list: FEATURE_ICONS},
      readOnly: true,
      description: 'Fixed per feature slot — change the icon in code (assets/icons.svg) if this ever needs to differ.',
    }),
    defineField({
      name: 'tone',
      title: 'Icon color',
      type: 'string',
      options: {list: FEATURE_TONES},
      readOnly: true,
    }),
  ],
  preview: {
    select: {title: 'title', subtitle: 'teaserDescription'},
  },
})
