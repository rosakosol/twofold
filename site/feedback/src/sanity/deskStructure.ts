import type {StructureResolver} from 'sanity/structure'

// "hero", each of the 6 features, the two legal pages, and the two quiz results are all
// singletons (exactly one document per fixed ID) — the site's HTML has a fixed number of
// slots for each (one hero, 6 feature cards, 2 legal pages, 2 quiz outcomes), so this is
// copy-only editing, not a free-form list editors add to or remove from. Document IDs
// here must match what site/assets/js/cms*.js queries by. FAQ items and quiz questions
// are the genuinely free-form lists.
const FEATURES = [
  {id: 'feature-relationship-globe', title: 'Relationship Globe'},
  {id: 'feature-live-flight-tracking', title: 'Live Flight Tracking'},
  {id: 'feature-memories', title: 'Memories'},
  {id: 'feature-couple-games', title: 'Couple Games'},
  {id: 'feature-widgets-live-activities', title: 'Widgets & Live Activities'},
  {id: 'feature-relationship-record', title: 'Relationship Record'},
]

const LEGAL_PAGES = [
  {id: 'legalPage-privacy', title: 'Privacy Policy'},
  {id: 'legalPage-terms', title: 'Terms of Use'},
]

const QUIZ_RESULTS = [
  {id: 'quizResult-plus', title: 'Result: Plus'},
  {id: 'quizResult-premium', title: 'Result: Premium'},
]

const PLANS = [
  {id: 'plan-plus', title: 'Plus'},
  {id: 'plan-premium', title: 'Premium'},
]

const MANAGED_TYPE_NAMES = new Set(['hero', 'feature', 'faqItem', 'legalPage', 'quizQuestion', 'quizResult', 'plan'])

export const structure: StructureResolver = (S) =>
  S.list()
    .title('Twofold Content')
    .items([
      S.listItem()
        .title('Home Hero')
        .id('hero')
        .child(S.document().schemaType('hero').documentId('hero')),
      S.divider(),
      S.listItem()
        .title('Features')
        .child(
          S.list()
            .title('Features')
            .items(
              FEATURES.map(({id, title}) =>
                S.listItem()
                  .title(title)
                  .id(id)
                  .child(S.document().schemaType('feature').documentId(id))
              )
            )
        ),
      S.listItem()
        .title('FAQ')
        .child(S.documentTypeList('faqItem').title('FAQ Items').defaultOrdering([{field: 'order', direction: 'asc'}])),
      S.listItem()
        .title('Pricing Plans')
        .child(
          S.list()
            .title('Pricing Plans')
            .items(
              PLANS.map(({id, title}) =>
                S.listItem()
                  .title(title)
                  .id(id)
                  .child(S.document().schemaType('plan').documentId(id))
              )
            )
        ),
      S.divider(),
      S.listItem()
        .title('Relationship Quiz')
        .child(
          S.list()
            .title('Relationship Quiz')
            .items([
              S.listItem()
                .title('Questions')
                .child(
                  S.documentTypeList('quizQuestion').title('Questions').defaultOrdering([{field: 'order', direction: 'asc'}])
                ),
              S.divider(),
              ...QUIZ_RESULTS.map(({id, title}) =>
                S.listItem()
                  .title(title)
                  .id(id)
                  .child(S.document().schemaType('quizResult').documentId(id))
              ),
            ])
        ),
      S.divider(),
      ...LEGAL_PAGES.map(({id, title}) =>
        S.listItem()
          .title(title)
          .id(id)
          .child(S.document().schemaType('legalPage').documentId(id))
      ),
      S.divider(),
      // Anything not covered above (there shouldn't be anything, but this keeps the
      // Studio from silently hiding a future schema type someone adds and forgets to
      // wire into this structure).
      ...S.documentTypeListItems().filter((item) => {
        const id = item.getId()
        return id ? !MANAGED_TYPE_NAMES.has(id) : true
      }),
    ])
