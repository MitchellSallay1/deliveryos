export function MarketingRiderPhone() {
  return (
    <div className="mx-auto w-[min(280px,100%)] rounded-[2rem] border-[10px] border-zinc-900 bg-zinc-900 p-2 shadow-2xl">
      <div className="overflow-hidden rounded-[1.4rem] bg-white">
        <div className="bg-zinc-900 px-4 py-2 text-center text-[10px] text-zinc-400">Rider PWA · demo</div>
        <div className="space-y-3 p-4">
          <p className="text-xs font-semibold uppercase text-zinc-500">Current job</p>
          <p className="text-lg font-semibold text-zinc-900">Paynesville drop-off</p>
          <div className="rounded-lg bg-zinc-50 p-3 text-sm">
            <p className="text-zinc-500">Customer</p>
            <p className="font-medium">Sample customer</p>
          </div>
          <div className="flex gap-2">
            <span className="flex-1 rounded-lg bg-[var(--color-accent)] py-2 text-center text-xs font-semibold text-black">
              Navigate
            </span>
            <span className="flex-1 rounded-lg border py-2 text-center text-xs font-medium">Photo POD</span>
          </div>
          <p className="text-[10px] text-zinc-400">GPS active during delivery · OTP when enabled</p>
        </div>
      </div>
    </div>
  )
}

export function MarketingButtonPhone() {
  return (
    <div className="mx-auto w-[min(260px,100%)]">
      <div className="rounded-3xl border-4 border-zinc-800 bg-zinc-100 p-4 shadow-xl">
        <div className="rounded-xl bg-zinc-800 px-3 py-2 font-mono text-[11px] leading-relaxed text-green-400">
          <p>New Delivery</p>
          <p className="text-zinc-300">Sinkor → Paynesville</p>
          <p className="mt-2 text-white">A Accept</p>
          <p>P Picked Up</p>
          <p>T In Transit</p>
          <p>D Delivered</p>
        </div>
        <div className="mt-4 grid grid-cols-3 gap-2">
          {['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'].map((k) => (
            <div key={k} className="flex h-10 items-center justify-center rounded-lg bg-white text-sm font-medium shadow-sm">
              {k}
            </div>
          ))}
        </div>
      </div>
      <p className="mt-3 text-center text-xs text-zinc-500">SMS/USSD when configured · not live by default</p>
    </div>
  )
}
