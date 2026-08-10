import { useState } from 'react'
import { Link } from 'react-router-dom'
import {
  CommandButton,
  CommandCard,
  CommandCardBody,
  CommandCardHeader,
  CommandInput,
  MetricList,
  MetricRow,
  SectionHeader,
  StatusChip,
} from '@/components/admin/control-tower'
import { statusColorFor } from '@/lib/admin-control-tower'
import { useSupportLookup } from '@/hooks/use-admin-platform'

export function AdminSupportPage() {
  const [query, setQuery] = useState('')
  const [submitted, setSubmitted] = useState('')
  const { data, isLoading } = useSupportLookup(submitted, submitted.length >= 2)

  const match = data?.match as string | null | undefined
  const company = data?.company as Record<string, unknown> | undefined
  const health = data?.health as { level: string; reasons: string[] } | undefined
  const usage = data?.usage as Record<string, unknown> | undefined
  const trackingCode = data?.tracking_code as string | undefined

  return (
    <div className="space-y-4">
      <SectionHeader eyebrow="Support" title="Support diagnostics" className="mb-0" />
      <CommandCard>
        <CommandCardBody className="space-y-4">
          <p className="text-sm text-zinc-500">
            Search by company phone/name or tracking code. No impersonation — read-only diagnostics.
          </p>
          <div className="flex max-w-md gap-2">
            <CommandInput value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Phone, company, tracking" />
            <CommandButton variant="primary" onClick={() => setSubmitted(query.trim())}>
              Lookup
            </CommandButton>
          </div>

          {isLoading && <p className="text-sm text-zinc-500">Searching…</p>}

          {submitted.length >= 2 && !isLoading && !match && (
            <p className="text-sm text-zinc-500">{String(data?.message ?? 'No company or tracking match.')}</p>
          )}
        </CommandCardBody>

        {match && company && (
          <>
            <CommandCardHeader
              title={match === 'delivery' ? `Delivery ${trackingCode}` : String(company.name)}
              description={match === 'delivery' ? String(company.name) : undefined}
              action={
                <Link to={`/admin/companies/${company.id}`} className="text-xs font-medium text-[#FFCB05] hover:underline">
                  Open Company 360 →
                </Link>
              }
            />
            <CommandCardBody className="space-y-4">
              {health && (
                <div className="flex flex-wrap items-center gap-2">
                  <StatusChip color={statusColorFor(health.level)} label={`health: ${health.level}`} />
                  {health.reasons?.map((r, i) => (
                    <span key={i} className="text-xs text-zinc-500">
                      {r}
                    </span>
                  ))}
                </div>
              )}
              <MetricList>
                <MetricRow label="Status" value={String(company.status ?? '—')} />
                <MetricRow label="Phone" value={String(company.phone ?? '—')} />
                <MetricRow label="Email" value={String(company.email ?? '—')} />
                <MetricRow label="SMS credits" value={String(company.sms_credits ?? '—')} />
                {usage && (
                  <MetricRow
                    label="Usage this period"
                    value={`${(usage.usage as Record<string, number> | undefined)?.deliveries_created ?? 0} deliveries`}
                  />
                )}
              </MetricList>
            </CommandCardBody>
          </>
        )}
      </CommandCard>
    </div>
  )
}
