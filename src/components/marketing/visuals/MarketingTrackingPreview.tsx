const STEPS = [
  { label: 'Order received', time: '09:12' },
  { label: 'Rider assigned', time: '09:18' },
  { label: 'Picked up', time: '09:42' },
  { label: 'In transit', time: '10:05' },
  { label: 'Delivered', time: '10:38' },
]

export function MarketingTrackingPreview() {
  return (
    <div className="mkt-panel mx-auto max-w-md overflow-hidden p-0 shadow-xl">
      <div className="border-b border-zinc-100 bg-zinc-50 px-5 py-4">
        <p className="text-xs font-semibold uppercase tracking-wider text-zinc-500">Track delivery</p>
        <p className="font-mono text-sm font-medium text-zinc-900">TRK-DEMO-1042</p>
        <p className="mt-1 text-sm text-zinc-600">Sample Merchant · Demo</p>
      </div>
      <div className="px-5 py-4">
        <div className="mb-4 h-24 rounded-xl bg-gradient-to-br from-zinc-100 to-zinc-200/80 p-3">
          <p className="text-[10px] font-medium uppercase text-zinc-500">Approximate rider area</p>
          <div className="mt-3 flex items-center gap-2">
            <span className="h-3 w-3 rounded-full bg-[var(--color-accent)] shadow-[0_0_12px_rgba(255,203,5,0.6)]" />
            <span className="text-xs text-zinc-600">Map preview · not live GPS</span>
          </div>
        </div>
        <ol className="space-y-0">
          {STEPS.map((s, i) => (
            <li key={s.label} className="relative flex gap-3 pb-4 last:pb-0">
              {i < STEPS.length - 1 && (
                <span className="absolute left-[7px] top-4 h-full w-px bg-zinc-200" aria-hidden />
              )}
              <span
                className={`relative z-10 mt-0.5 h-4 w-4 shrink-0 rounded-full border-2 ${
                  i === STEPS.length - 1 ? 'border-[var(--color-accent)] bg-[var(--color-accent)]' : 'border-zinc-300 bg-white'
                }`}
              />
              <div>
                <p className="text-sm font-medium text-zinc-900">{s.label}</p>
                <p className="text-xs text-zinc-500">{s.time}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>
    </div>
  )
}
