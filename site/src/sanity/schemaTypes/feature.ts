import {defineField, defineType} from 'sanity'

// Values match the symbol ids in public/assets/icons.svg minus the `icon-` prefix —
// featuresFallback.ts re-adds it. Adding a new icon here means adding the matching
// <symbol id="icon-…"> to that sprite too.
export const FEATURE_ICONS = [
  {title: 'Globe', value: 'globe'},
  {title: 'Plane', value: 'plane'},
  {title: 'Pin', value: 'pin'},
  {title: 'Gamepad', value: 'gamepad'},
  {title: 'Grid', value: 'grid'},
  {title: 'File download', value: 'file-download'},
  {title: 'Heart', value: 'heart'},
  {title: 'Bell', value: 'bell'},
  {title: 'Users', value: 'users'},
  {title: 'Lock', value: 'lock'},
  {title: 'Shield', value: 'shield'},
  {title: 'Sparkle', value: 'sparkle'},
  {title: 'Check circle', value: 'check-circle'},
  {title: 'QR code', value: 'qr'},
]

export const FEATURE_TONES = [
  {title: 'Sky blue', value: 'sky'},
  {title: 'Leaf green', value: 'green'},
  {title: 'Heart red', value: 'red'},
  {title: 'Ink', value: 'ink'},
]

// One document per feature card. This is a free-form list — editors add, remove, rename,
// and reorder features in Studio, and both the home page teaser grid and /features detail
// sections render whatever is here, in `order`. The only thing still fixed in code is the
// per-feature illustration on /features (FeatureArt, keyed by slug); a feature whose slug
// has no illustration falls back to a generic mock card. See site/README.md "Content model".
export default defineType({
  name: 'feature',
  title: 'Feature',
  type: 'document',
  fields: [
    defineField({name: 'title', title: 'Title', type: 'string', validation: (Rule) => Rule.required()}),
    defineField({
      name: 'slug',
      title: 'Slug',
      type: 'slug',
      options: {source: 'title', maxLength: 60},
      description:
        'Identifies this feature in code — picks the illustration shown on the features page. Renaming the title is safe; changing the slug swaps the illustration.',
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'order',
      title: 'Order',
      type: 'number',
      description: 'Lowest first, on both the home page grid and the features page.',
      validation: (Rule) => Rule.required().integer().min(0),
    }),
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
      title: 'Feature bullets (features page)',
      type: 'array',
      of: [{type: 'string'}],
      validation: (Rule) => Rule.min(1).max(4),
    }),
    defineField({
      name: 'icon',
      title: 'Icon',
      type: 'string',
      options: {list: FEATURE_ICONS},
      validation: (Rule) => Rule.required(),
    }),
    defineField({
      name: 'tone',
      title: 'Icon color',
      type: 'string',
      options: {list: FEATURE_TONES},
      validation: (Rule) => Rule.required(),
    }),
  ],
  orderings: [{title: 'Order', name: 'orderAsc', by: [{field: 'order', direction: 'asc'}]}],
  preview: {
    select: {title: 'title', subtitle: 'teaserDescription', order: 'order'},
    prepare: ({title, subtitle, order}) => ({
      title: order === undefined || order === null ? title : `${order}. ${title}`,
      subtitle,
    }),
  },
})
