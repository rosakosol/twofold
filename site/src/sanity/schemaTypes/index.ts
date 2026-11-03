import legalPage from './legalPage'
import quizQuestion from './quizQuestion'
import quizResult from './quizResult'
import plan from './plan'

// FAQ used to be here (`faqItem`) — retired in favor of a custom tool over the Supabase
// `faq_entries` table, shared with the iOS app's Support screen. See src/sanity/tools/FaqTool.tsx
// and src/sanity/config.ts's `tools` entry.
// The home hero (`hero`), the feature cards (`feature`) and the pricing comparison table
// (`planComparison`) went the same way: that copy now lives in code (docs/TWOFOLD_WEBSITE.md), and
// nothing on the site read those documents, so editing them in Studio changed nothing. The
// documents themselves are still in the dataset; Studio just no longer offers them.
export const schemaTypes = [legalPage, quizQuestion, quizResult, plan]
