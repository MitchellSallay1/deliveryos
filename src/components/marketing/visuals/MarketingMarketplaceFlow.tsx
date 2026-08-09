const NODES = ['Merchant', 'Delivery request', 'Provider network', 'Rider', 'Customer']

export function MarketingMarketplaceFlow() {
  return (
    <div className="flex flex-col items-center gap-2 py-4 md:flex-row md:justify-center md:gap-0">
      {NODES.map((label, i) => (
        <div key={label} className="flex flex-col items-center md:flex-row">
          <div className="rounded-xl border border-white/15 bg-white/5 px-5 py-3 text-center backdrop-blur-sm">
            <p className="text-sm font-medium text-white">{label}</p>
          </div>
          {i < NODES.length - 1 && (
            <span className="my-1 text-[var(--color-accent)] md:mx-3 md:my-0" aria-hidden>
              ↓
            </span>
          )}
        </div>
      ))}
    </div>
  )
}
