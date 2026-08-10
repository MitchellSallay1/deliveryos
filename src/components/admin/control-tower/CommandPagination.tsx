import { CommandButton } from './CommandButton'

/** Single canonical pager used across every paginated admin table. */
export function CommandPagination({
  total,
  page,
  pageSize,
  onPage,
  loading,
}: {
  total: number
  page: number
  pageSize: number
  onPage: (page: number) => void
  loading?: boolean
}) {
  const start = total === 0 ? 0 : (page - 1) * pageSize + 1
  const end = Math.min(page * pageSize, total)

  return (
    <div className="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-zinc-500">
      <span>
        {total === 0 ? 'No results' : `${start}–${end} of ${total}`}
      </span>
      <div className="flex gap-2">
        <CommandButton size="sm" disabled={page <= 1 || loading} onClick={() => onPage(page - 1)}>
          Previous
        </CommandButton>
        <CommandButton size="sm" disabled={page * pageSize >= total || loading} onClick={() => onPage(page + 1)}>
          Next
        </CommandButton>
      </div>
    </div>
  )
}
