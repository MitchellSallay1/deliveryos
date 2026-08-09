export function RiderPhonePreview() {
  return (
    <div className="w-[min(200px,45vw)] shrink-0 rounded-[1.75rem] border-[8px] border-zinc-800 bg-zinc-900 p-1.5 shadow-2xl">
      <div className="overflow-hidden rounded-[1.25rem] bg-white">
        <div className="bg-zinc-900 px-3 py-2 text-center text-[10px] font-medium text-zinc-400">My Jobs · demo</div>
        <div className="p-3">
          <p className="text-[10px] uppercase text-zinc-500">Active delivery</p>
          <p className="mt-1 text-sm font-semibold text-zinc-900">Sinkor → Paynesville</p>
          <p className="mt-2 text-xs text-zinc-600">Customer: Sample · COD LRD 3,600</p>
          <div className="mt-4 space-y-2">
            <div className="rounded-lg bg-[#FFCB05] py-2 text-center text-xs font-bold text-black">Accept job</div>
            <div className="rounded-lg border py-2 text-center text-xs font-medium text-zinc-700">Navigate</div>
          </div>
        </div>
      </div>
    </div>
  )
}
