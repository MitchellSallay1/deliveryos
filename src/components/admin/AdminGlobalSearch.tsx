import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Building2, Package, Search, Truck, User } from 'lucide-react'
import { useAdminGlobalSearch } from '@/hooks/use-admin-platform'
import { clampSearchIndex } from '@/lib/admin-control-tower'
import { cn } from '@/lib/utils'

const KIND_ICON: Record<string, typeof Building2> = {
  company: Building2,
  delivery: Package,
  rider: Truck,
  user: User,
}

const KIND_LABEL: Record<string, string> = {
  company: 'Company',
  delivery: 'Delivery',
  rider: 'Rider',
  user: 'User',
}

/**
 * Cmd/Ctrl+K command palette. Opens as a centered modal (not an inline
 * dropdown), auto-focuses the input, and supports arrow-key navigation +
 * Enter to select — the keyboard-first UX the control tower needs.
 */
export function AdminGlobalSearch() {
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(0)
  const navigate = useNavigate()
  const inputRef = useRef<HTMLInputElement>(null)
  const { data, isFetching } = useAdminGlobalSearch(query, open)

  const results = useMemo(() => data?.results ?? [], [data])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setOpen(true)
      }
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  useEffect(() => {
    if (open) {
      // Wait a tick for the modal to mount before focusing.
      const id = window.setTimeout(() => inputRef.current?.focus(), 0)
      return () => window.clearTimeout(id)
    }
    setQuery('')
    setActiveIndex(0)
  }, [open])

  useEffect(() => {
    setActiveIndex(0)
  }, [results.length])

  function select(href: string) {
    setOpen(false)
    navigate(href)
  }

  function onInputKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActiveIndex((i) => clampSearchIndex(i, 'down', results.length))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActiveIndex((i) => clampSearchIndex(i, 'up', results.length))
    } else if (e.key === 'Enter') {
      const target = results[activeIndex]
      if (target) select(target.href)
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex h-9 w-full max-w-md flex-1 items-center gap-2 rounded-lg border border-white/[0.08] bg-white/[0.03] px-3 text-left text-sm text-zinc-500 transition hover:border-white/[0.15] hover:bg-white/[0.05]"
      >
        <Search className="h-4 w-4 shrink-0" aria-hidden />
        <span className="flex-1 truncate">Search companies, deliveries, riders, users…</span>
        <kbd className="hidden shrink-0 items-center gap-0.5 rounded border border-white/10 bg-white/5 px-1.5 py-0.5 text-[10px] font-medium text-zinc-400 sm:inline-flex">
          ⌘K
        </kbd>
      </button>

      {open && (
        <div className="fixed inset-0 z-[100] flex items-start justify-center bg-black/70 px-4 pt-[12vh] backdrop-blur-sm">
          <div
            className="absolute inset-0"
            onClick={() => setOpen(false)}
            aria-hidden
          />
          <div className="relative w-full max-w-xl overflow-hidden rounded-xl border border-white/10 bg-[#131316] shadow-2xl">
            <div className="flex items-center gap-2 border-b border-white/[0.08] px-4 py-3">
              <Search className="h-4 w-4 shrink-0 text-zinc-500" aria-hidden />
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={onInputKeyDown}
                placeholder="Search the platform…"
                className="flex-1 bg-transparent text-sm text-white placeholder:text-zinc-600 focus:outline-none"
                aria-label="Global admin search"
              />
              <kbd className="rounded border border-white/10 bg-white/5 px-1.5 py-0.5 text-[10px] text-zinc-500">
                Esc
              </kbd>
            </div>
            <div className="max-h-80 overflow-y-auto">
              {query.trim().length < 2 && (
                <p className="px-4 py-6 text-center text-sm text-zinc-600">
                  Type at least 2 characters to search companies, deliveries, riders, and users.
                </p>
              )}
              {query.trim().length >= 2 && isFetching && (
                <p className="px-4 py-6 text-center text-sm text-zinc-500">Searching…</p>
              )}
              {query.trim().length >= 2 && !isFetching && results.length === 0 && (
                <p className="px-4 py-6 text-center text-sm text-zinc-500">No matches for &ldquo;{query}&rdquo;</p>
              )}
              {results.length > 0 && (
                <ul>
                  {results.map((r, i) => {
                    const Icon = KIND_ICON[r.kind] ?? Building2
                    return (
                      <li key={`${r.kind}-${r.id}`}>
                        <button
                          type="button"
                          onMouseEnter={() => setActiveIndex(i)}
                          onClick={() => select(r.href)}
                          className={cn(
                            'flex w-full items-center gap-3 px-4 py-2.5 text-left text-sm transition-colors',
                            i === activeIndex ? 'bg-white/[0.06] text-white' : 'text-zinc-300',
                          )}
                        >
                          <Icon className="h-4 w-4 shrink-0 text-zinc-500" aria-hidden />
                          <span className="min-w-0 flex-1 truncate">{r.label}</span>
                          <span className="shrink-0 rounded bg-white/5 px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-zinc-500">
                            {KIND_LABEL[r.kind] ?? r.kind}
                          </span>
                        </button>
                      </li>
                    )
                  })}
                </ul>
              )}
            </div>
            <button
              type="button"
              onClick={() => {
                setOpen(false)
                navigate('/admin/support')
              }}
              className="block w-full border-t border-white/[0.08] px-4 py-2.5 text-left text-xs text-zinc-500 hover:bg-white/[0.03] hover:text-zinc-300"
            >
              Advanced support lookup →
            </button>
          </div>
        </div>
      )}
    </>
  )
}
