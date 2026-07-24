import hero from './hero'
import feature from './feature'
import legalPage from './legalPage'
import quizQuestion from './quizQuestion'
import quizResult from './quizResult'
import plan from './plan'

// FAQ used to be here (`faqItem`) — retired in favor of a custom tool over the Supabase
// `faq_entries` table, shared with the iOS app's Support screen. See src/sanity/tools/FaqTool.tsx
// and src/sanity/config.ts's `tools` entry.
export const schemaTypes = [hero, feature, legalPage, quizQuestion, quizResult, plan]
