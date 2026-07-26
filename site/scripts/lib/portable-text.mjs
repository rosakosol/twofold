// Minimal Portable Text builders for the block subset legalPage.ts allows: h2/normal blocks,
// bullet lists, and `strong` / `em` / `link` marks. Keys are deterministic (seeded documents
// should be reproducible), hence the running counter rather than a random id.
//
//   h2('Heading')
//   p(span('plain '), span('bold', 'strong'), link('a link', 'https://…'))
//   li(span('bullet text'))

let keySeq = 0

/** Restart key numbering — call once per document so ids don't drift between runs. */
export function resetKeys() {
  keySeq = 0
}

const key = () => `k${(keySeq++).toString(36)}`

/** span(text) | span(text, 'strong'|'em') | span(text, {_key}) for a hoisted mark */
export function span(text, mark) {
  if (!mark) return {_type: 'span', _key: key(), text, marks: []}
  if (typeof mark === 'string') return {_type: 'span', _key: key(), text, marks: [mark]}
  return {_type: 'span', _key: key(), text, marks: [mark._key]}
}

export const link = (text, href) => ({href, text})

function block(style, children, extra = {}) {
  const markDefs = []
  const spans = children.map((child) => {
    if (child._type === 'span') return child
    // A link: {text, href} — hoisted into markDefs and referenced by key.
    const linkKey = key()
    markDefs.push({_type: 'link', _key: linkKey, href: child.href})
    return span(child.text, {_key: linkKey})
  })
  return {_type: 'block', _key: key(), style, markDefs, children: spans, ...extra}
}

export const h2 = (text) => block('h2', [span(text)])
export const p = (...children) => block('normal', children)
export const li = (...children) => block('normal', children, {listItem: 'bullet', level: 1})

/** Convenience for the common "one plain string" cases. */
export const ptext = (text) => p(span(text))
export const bullet = (text) => li(span(text))
