import {useEffect, useState} from 'react'
import {Badge, Card, Flex, Spinner, Stack, Text} from '@sanity/ui'
import {useFormValue, type StringInputProps} from 'sanity'
import {PLANS, type PlanId} from '@/lib/marketing/config'
import {anonymousAppUserId, fetchLivePrices, type LivePrices} from '@/lib/marketing/billing'
import {perMonthLabelFor, priceLabelFor} from '@/lib/marketing/priceDisplay'

// Read-only price display for the `plan` documents.
//
// Prices are Stripe's, not Sanity's — /pricing reads them straight off the RevenueCat offering
// and only falls back to the stored label. An editable field here was therefore a trap: typing
// "$7.99" changed the marketing copy, never the charge, and the two silently disagreed. So the
// fields are readOnly and this renders what a visitor will actually be charged, fetched live.
//
// Uses the same public Web Billing key the pricing page does. It is NEXT_PUBLIC_, so it is
// already in the Studio bundle, and it only grants what any visitor to /pricing can read.

export type PriceKind = 'monthly' | 'yearlyTotal' | 'yearlyPerMonth'

// Keyed off the field name rather than a schema option: Sanity's StringOptions is a closed
// type, and augmenting it to smuggle one string through is more machinery than three names.
//
// Read from `props.path`, NOT `props.schemaType.name` - the latter is the underlying type
// ("string"), so every field looked the same and all three rendered the monthly price.
const KIND_BY_FIELD: Record<string, PriceKind> = {
  monthlyPriceLabel: 'monthly',
  yearlyPriceLabel: 'yearlyTotal',
  yearlyPerMonthLabel: 'yearlyPerMonth',
}

// One fetch shared by all three fields on the document, rather than three identical ones.
let pricesPromise: Promise<LivePrices> | null = null
function loadPrices(): Promise<LivePrices> {
  if (!pricesPromise) {
    pricesPromise = (async () => {
      const appUserId = await anonymousAppUserId()
      return appUserId ? fetchLivePrices(appUserId) : {}
    })()
  }
  return pricesPromise
}

/** `plan-premium` / `drafts.plan-premium` -> `premium`. */
function planIdFromDocument(documentId: unknown): PlanId | null {
  if (typeof documentId !== 'string') return null
  const bare = documentId.replace(/^drafts\./, '').replace(/^plan-/, '')
  return bare === 'plus' || bare === 'premium' ? bare : null
}

export function LivePriceInput(props: StringInputProps) {
  const documentId = useFormValue(['_id'])
  const planId = planIdFromDocument(documentId)
  // Last path segment is the field name. Deliberately no default: guessing a kind is what
  // turned a wiring mistake into three fields confidently showing the wrong price.
  const fieldName = String(props.path[props.path.length - 1] ?? '')
  const kind: PriceKind | undefined = KIND_BY_FIELD[fieldName]

  const [prices, setPrices] = useState<LivePrices | null>(null)

  useEffect(() => {
    let cancelled = false
    loadPrices().then((result) => {
      if (!cancelled) setPrices(result)
    })
    return () => {
      cancelled = true
    }
  }, [])

  if (!kind) {
    return (
      <Card padding={3} radius={2} tone="critical" border>
        <Text size={1}>
          LivePriceInput is attached to <code>{fieldName || '(unknown field)'}</code>, which it
          has no price mapping for. Add it to KIND_BY_FIELD.
        </Text>
      </Card>
    )
  }

  const storedLabel = props.value ?? ''
  const codeDefault = planId
    ? kind === 'monthly'
      ? PLANS[planId].monthly.priceLabel
      : kind === 'yearlyTotal'
        ? PLANS[planId].yearly.priceLabel
        : PLANS[planId].yearly.perMonthLabel ?? ''
    : ''

  // What the site will show if RevenueCat has nothing: the stored label, else the code default.
  const fallback = storedLabel || codeDefault

  let live: string | null = null
  if (prices && planId) {
    const packageId = kind === 'monthly' ? PLANS[planId].monthly.packageId : PLANS[planId].yearly.packageId
    const resolved =
      kind === 'yearlyPerMonth'
        ? perMonthLabelFor(prices, packageId, '')
        : priceLabelFor(prices, packageId, '')
    live = resolved || null
  }

  if (!prices) {
    return (
      <Card padding={3} radius={2} tone="transparent" border>
        <Flex align="center" gap={3}>
          <Spinner muted />
          <Text size={1} muted>
            Reading the live price from RevenueCat…
          </Text>
        </Flex>
      </Card>
    )
  }

  return (
    <Card padding={3} radius={2} tone={live ? 'positive' : 'caution'} border>
      <Stack gap={3}>
        <Flex align="center" gap={2}>
          <Text size={3} weight="semibold">
            {live ?? fallback ?? '—'}
          </Text>
          <Badge tone={live ? 'positive' : 'caution'} fontSize={0}>
            {live ? 'live from Stripe' : 'fallback'}
          </Badge>
        </Flex>

        {live ? (
          <Text size={1} muted>
            What a visitor is actually charged, in their own currency. Change it in Stripe — this
            field can&apos;t, and editing it here would only have moved the label.
          </Text>
        ) : (
          <Text size={1} muted>
            RevenueCat returned no price for this package, so the site is showing{' '}
            <strong>{fallback || 'nothing'}</strong> from the fallback. Usually means the offering
            isn&apos;t published, or the package identifier doesn&apos;t match the one in config.ts.
          </Text>
        )}
      </Stack>
    </Card>
  )
}
