// Shared by the scripts/ seed scripts. Resolves the Sanity project/dataset from .env.local
// (which isn't loaded outside Next) and a write token from SANITY_AUTH_TOKEN, falling back to
// the credential `sanity login` already stored in ~/.config/sanity/config.json.
import {createClient} from '@sanity/client'
import {readFileSync} from 'node:fs'
import {homedir} from 'node:os'
import {join} from 'node:path'

function envFromLocalFile() {
  const out = {}
  try {
    const path = new URL('../../.env.local', import.meta.url)
    for (const line of readFileSync(path, 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)$/)
      if (m) out[m[1]] = m[2].trim().replace(/^["']|["']$/g, '')
    }
  } catch {
    /* fall through to process.env */
  }
  return out
}

function cliAuthToken() {
  try {
    return JSON.parse(readFileSync(join(homedir(), '.config', 'sanity', 'config.json'), 'utf8')).authToken
  } catch {
    return undefined
  }
}

export function sanityWriteClient() {
  const fileEnv = envFromLocalFile()
  const projectId = process.env.NEXT_PUBLIC_SANITY_PROJECT_ID || fileEnv.NEXT_PUBLIC_SANITY_PROJECT_ID
  const dataset = process.env.NEXT_PUBLIC_SANITY_DATASET || fileEnv.NEXT_PUBLIC_SANITY_DATASET
  const token = process.env.SANITY_AUTH_TOKEN || cliAuthToken()

  if (!projectId || !dataset) throw new Error('Missing NEXT_PUBLIC_SANITY_PROJECT_ID / NEXT_PUBLIC_SANITY_DATASET')
  if (!token) throw new Error('No Sanity write token — set SANITY_AUTH_TOKEN, or run `npx sanity login`')

  const client = createClient({projectId, dataset, apiVersion: '2024-01-01', token, useCdn: false})
  return {client, projectId, dataset}
}
