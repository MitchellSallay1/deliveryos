import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Search } from 'lucide-react'
import { Input } from '@/components/ui/Input'
import { useAdminGlobalSearch } from '@/hooks/use-admin-platform'

export function AdminGlobalSearch() {
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const navigate = useNavigate()
  const { data, isFetching } = useAdminGlobalSearch(query, open)

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault()
        setOpen(true)
      }
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const results = data?.results ?? []

  return (
    <div className="relative max-w-md flex-1">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted)]" />
        <Input
          className="pl-9"
          placeholder="Search platform (⌘K)"
          value={query}
          onFocus={() => setOpen(true)}
          onChange={(e) => {
            setQuery(e.target.value)
            setOpen(true)
          }}
          aria-label="Global admin search"
          aria-expanded={open}
        />
      </div>
      {open && query.trim().length >= 2 && (
        <div className="absolute z-50 mt-1 w-full rounded-lg border bg-white shadow-lg">
          {isFetching && <p className="px-3 py-2 text-xs text-[var(--color-muted)]">Searching…</p>}
          {!isFetching && results.length === 0 && (
            <p className="px-3 py-2 text-xs text-[var(--color-muted)]">No matches</p>
          )}
          <ul>
            {results.map((r) => (
              <li key={`${r.kind}-${r.id}`}>
                <button
                  type="button"
                  className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-zinc-50"
                  onClick={() => {
                    setOpen(false)
                    setQuery('')
                    navigate(r.href)
                  }}
                >
                  <span className="text-[10px] uppercase text-[var(--color-muted)]">{r.kind}</span>
                  {r.label}
                </button>
              </li>
            ))}
          </ul>
          <Link
            to="/admin/support"
            className="block border-t px-3 py-2 text-xs text-[var(--color-muted)] hover:bg-zinc-50"
            onClick={() => setOpen(false)}
          >
            Advanced support lookup →
          </Link>
        </div>
      )}
    </div>
  )
}
