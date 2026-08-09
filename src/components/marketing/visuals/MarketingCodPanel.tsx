export function MarketingCodPanel({ compact }: { compact?: boolean }) {
  return (
    <div className="rounded-2xl border border-zinc-200 bg-zinc-950 px-4 py-3 text-white shadow-xl">
      <p className="text-[10px] font-semibold uppercase tracking-wider text-zinc-400">COD · demo</p>
      <p className={compact ? 'mt-1 text-lg font-semibold tabular-nums' : 'mt-2 text-2xl font-semibold tabular-nums'}>
        LRD 12,400
      </p>
      {!compact && (
        <dl className="mt-3 grid grid-cols-2 gap-2 text-xs text-zinc-400">
          <div>
            <dt>Collected</dt>
            <dd className="text-white">LRD 8,200</dd>
          </div>
          <div>
            <dt>Outstanding</dt>
            <dd className="text-[var(--color-accent)]">LRD 4,200</dd>
          </div>
        </dl>
      )}
      <p className="mt-2 text-[9px] text-zinc-500">Presentation values only</p>
    </div>
  )
}
