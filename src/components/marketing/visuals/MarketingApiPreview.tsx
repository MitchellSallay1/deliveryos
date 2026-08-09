export function MarketingApiPreview() {
  return (
    <div className="overflow-hidden rounded-2xl border border-zinc-800 bg-zinc-950 shadow-2xl">
      <div className="flex items-center gap-2 border-b border-white/10 px-4 py-2">
        <span className="h-2.5 w-2.5 rounded-full bg-red-500/80" />
        <span className="h-2.5 w-2.5 rounded-full bg-amber-500/80" />
        <span className="h-2.5 w-2.5 rounded-full bg-emerald-500/80" />
        <span className="ml-2 text-xs text-zinc-500">api-v1 · documented</span>
      </div>
      <pre className="overflow-x-auto p-4 text-xs leading-relaxed text-zinc-300">
        <code>{`POST /v1/deliveries
Authorization: Bearer dos_live_••••

{
  "pickup_business_name": "Warehouse A",
  "pickup_address": "Sinkor, Monrovia",
  "customer_name": "Jane Doe",
  "customer_phone": "+231…",
  "destination_address": "Paynesville",
  "amount_to_collect_lrd_cents": 0
}`}</code>
      </pre>
      <p className="border-t border-white/10 px-4 py-2 text-[10px] text-zinc-500">
        See docs/API.md · Webhooks with signed payloads
      </p>
    </div>
  )
}
