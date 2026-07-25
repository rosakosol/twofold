import type {StructureResolver} from 'sanity/structure'

// "hero", the two legal pages, the two plans, and the two quiz results are singletons
// (exactly one document per fixed ID) — the site has a fixed number of slots for each
// (one hero, 2 legal pages, 2 plans, 2 quiz outcomes), so those are copy-only editing.
// Features and quiz questions are free-form lists editors add to and remove from, so
// they get a plain document list instead. FAQ moved to its own custom tool (see
// config.ts's `tools` entry), since it's no longer a Sanity document type at all.
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

const MANAGED_TYPE_NAMES = new Set(['hero', 'feature', 'legalPage', 'quizQuestion', 'quizResult', 'plan'])

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
        .child(S.documentTypeList('feature').title('Features').defaultOrdering([{field: 'order', direction: 'asc'}])),
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
