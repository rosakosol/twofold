import {defineConfig} from 'sanity'
import {structureTool} from 'sanity/structure'
import {visionTool} from '@sanity/vision'
import {schemaTypes} from './schemaTypes'
import {structure} from './deskStructure'

// Editing UI for twofoldapp.com.au's marketing copy — hero text, feature copy, FAQ
// entries, and the two legal pages. Layout, nav, and all Stripe/RevenueCat pricing
// stay hardcoded in the site itself (see site/README.md "Content model" for the
// boundary between what's editable here vs. what lives in code).
export default defineConfig({
  name: 'default',
  title: 'Twofold Website',

  projectId: 'fck477cu',
  dataset: 'production',

  plugins: [structureTool({structure}), visionTool()],

  schema: {
    types: schemaTypes,
  },
})
