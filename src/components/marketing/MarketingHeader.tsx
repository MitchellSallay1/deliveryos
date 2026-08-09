import { useEffect, useRef, useState } from 'react'
import { Link, NavLink, useLocation } from 'react-router-dom'
import { ChevronDown, Menu, X } from 'lucide-react'
import { BrandLogo } from '@/components/brand/BrandLogo'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/utils'
import {
  MARKETING_COMPANY_LINKS,
  MARKETING_PRIMARY_NAV,
  MARKETING_PRODUCT_MEGA_COLUMNS,
  MARKETING_PRODUCT_TOUR_HREF,
  isFeaturesRoute,
  isProductNavActive,
} from '@/lib/marketing-nav'
import { MARKETING_CTA_TRIAL } from '@/lib/marketing-cta'

export function MarketingHeader() {
  const { pathname } = useLocation()
  const isHome = pathname === '/'
  const darkNav = isHome || isFeaturesRoute(pathname)
  const [open, setOpen] = useState(false)
  const [scrolled, setScrolled] = useState(false)
  const [mega, setMega] = useState<'product' | 'company' | null>(null)
  const [mobileMega, setMobileMega] = useState<string | null>(null)
  const megaRootRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  useEffect(() => {
    setMega(null)
    setOpen(false)
    setMobileMega(null)
  }, [pathname])

  useEffect(() => {
    if (!mega) return
    const onPointer = (e: MouseEvent) => {
      if (!megaRootRef.current?.contains(e.target as Node)) setMega(null)
    }
    document.addEventListener('mousedown', onPointer)
    return () => document.removeEventListener('mousedown', onPointer)
  }, [mega])

  const productActive = isProductNavActive(pathname)

  return (
    <header
      className={cn(
        'sticky top-0 z-50 border-b transition-colors duration-300',
        darkNav
          ? cn('border-white/5', scrolled ? 'bg-[#11110F]/95 backdrop-blur-xl' : 'bg-[#11110F]/85 backdrop-blur-md')
          : cn('border-zinc-200/60', scrolled ? 'bg-[#faf9f7]/85 backdrop-blur-xl' : 'bg-[#faf9f7]/70 backdrop-blur-md'),
      )}
    >
      <div ref={megaRootRef} className="relative">
        <div className="mx-auto flex h-[72px] max-w-[1440px] items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
          <Link to="/" className="shrink-0" onClick={() => setOpen(false)}>
            {darkNav ? (
              <div className="flex flex-col gap-0.5">
                <BrandLogo variant="light" showPartner={false} />
                <p className="pl-11 text-[10px] text-zinc-500">
                  Powered by <span className="font-semibold text-[#FFCB05]">MTN</span>
                </p>
              </div>
            ) : (
              <BrandLogo showPartner={false} />
            )}
          </Link>

          <nav className="hidden items-center gap-0.5 xl:flex" aria-label="Primary">
            {MARKETING_PRIMARY_NAV.map((item) =>
              item.mega === 'product' ? (
                <div
                  key={item.id}
                  className="relative flex items-center"
                  onMouseEnter={() => setMega('product')}
                  onMouseLeave={() => setMega(null)}
                >
                  <Link
                    to={MARKETING_PRODUCT_TOUR_HREF}
                    className={cn(
                      'rounded-lg px-3 py-2 text-sm font-medium transition',
                      darkNav ? 'text-zinc-300 hover:text-white' : 'text-zinc-600 hover:text-zinc-900',
                      productActive && (darkNav ? 'text-white' : 'text-zinc-900'),
                    )}
                    onClick={() => setMega(null)}
                  >
                    {item.label}
                  </Link>
                  <button
                    type="button"
                    className={cn(
                      'rounded-lg p-2 transition',
                      darkNav ? 'text-zinc-400 hover:text-white' : 'text-zinc-500 hover:text-zinc-900',
                    )}
                    aria-expanded={mega === 'product'}
                    aria-label="Open product menu"
                    onClick={() => setMega((m) => (m === 'product' ? null : 'product'))}
                  >
                    <ChevronDown className={cn('h-4 w-4 transition', mega === 'product' && 'rotate-180')} />
                  </button>
                </div>
              ) : item.mega === 'company' ? (
                <div
                  key={item.id}
                  className="relative flex items-center"
                  onMouseEnter={() => setMega('company')}
                  onMouseLeave={() => setMega(null)}
                >
                  <span
                    className={cn(
                      'cursor-default rounded-lg px-3 py-2 text-sm font-medium',
                      darkNav ? 'text-zinc-300' : 'text-zinc-600',
                    )}
                  >
                    {item.label}
                  </span>
                  <button
                    type="button"
                    className="rounded-lg p-2"
                    aria-expanded={mega === 'company'}
                    aria-label="Open company menu"
                    onClick={() => setMega((m) => (m === 'company' ? null : 'company'))}
                  >
                    <ChevronDown className={cn('h-4 w-4', mega === 'company' && 'rotate-180')} />
                  </button>
                </div>
              ) : (
                <NavLink
                  key={item.id}
                  to={item.to!}
                  className={({ isActive }) =>
                    cn(
                      'rounded-lg px-3 py-2 text-sm font-medium transition',
                      darkNav ? 'text-zinc-300 hover:text-white' : 'text-zinc-600 hover:text-zinc-900',
                      isActive && (darkNav ? 'text-white' : 'text-zinc-900'),
                    )
                  }
                  onClick={() => setMega(null)}
                >
                  {item.label}
                </NavLink>
              ),
            )}
          </nav>

          <div className="hidden items-center gap-2 xl:flex">
            <Link to="/login">
              <Button
                variant="ghost"
                type="button"
                className={darkNav ? 'text-zinc-200 hover:bg-white/10 hover:text-white' : undefined}
              >
                Sign in
              </Button>
            </Link>
            <Link to="/register">
              <Button variant="accent" type="button" className="rounded-xl px-5 font-semibold">
                {MARKETING_CTA_TRIAL}
              </Button>
            </Link>
          </div>

          <button
            type="button"
            className={cn('rounded-lg p-2 xl:hidden', darkNav ? 'text-zinc-100' : 'text-zinc-800')}
            aria-label={open ? 'Close menu' : 'Open menu'}
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
          </button>
        </div>

        {mega && (
          <div
            className="absolute left-0 right-0 top-full z-50 hidden px-4 pt-2 xl:block sm:px-6 lg:px-8"
            onMouseEnter={() => setMega(mega)}
            onMouseLeave={() => setMega(null)}
          >
            <div
              className={cn(
                'mx-auto max-w-[1440px] rounded-2xl border p-6 shadow-2xl',
                darkNav ? 'border-white/10 bg-[#1a1a18]/98 backdrop-blur-xl' : 'border-zinc-200 bg-white',
              )}
            >
              {mega === 'product' ? (
                <div className="grid gap-8 sm:grid-cols-2 lg:grid-cols-4">
                  {MARKETING_PRODUCT_MEGA_COLUMNS.map((col) => (
                    <div key={col.heading}>
                      <p
                        className={cn(
                          'text-xs font-bold uppercase tracking-widest',
                          darkNav ? 'text-zinc-500' : 'text-zinc-400',
                        )}
                      >
                        {col.heading}
                      </p>
                      <ul className="mt-3 space-y-2">
                        {col.links.map((link) => (
                          <li key={link.label + link.to}>
                            <Link
                              to={link.to}
                              className={cn(
                                'block rounded-lg p-2 transition',
                                darkNav ? 'hover:bg-white/5' : 'hover:bg-zinc-50',
                              )}
                              onClick={() => setMega(null)}
                            >
                              <p className={cn('text-sm font-semibold', darkNav ? 'text-white' : 'text-zinc-900')}>
                                {link.label}
                              </p>
                              {link.description && (
                                <p className="text-xs text-zinc-500">{link.description}</p>
                              )}
                            </Link>
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="grid gap-4 sm:grid-cols-2">
                  {MARKETING_COMPANY_LINKS.map((link) => (
                    <Link
                      key={link.to}
                      to={link.to}
                      className={cn('rounded-lg p-3', darkNav ? 'hover:bg-white/5' : 'hover:bg-zinc-50')}
                      onClick={() => setMega(null)}
                    >
                      <p className={cn('text-sm font-semibold', darkNav ? 'text-white' : 'text-zinc-900')}>
                        {link.label}
                      </p>
                    </Link>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {open && (
        <nav
          className={cn(
            'border-t px-4 py-4 xl:hidden',
            darkNav ? 'border-white/10 bg-[#11110F]' : 'border-zinc-200 bg-[#faf9f7]',
          )}
          aria-label="Mobile"
        >
          <div className="flex flex-col gap-1">
            <button
              type="button"
              className={cn(
                'flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-sm font-medium',
                darkNav && 'text-zinc-200',
              )}
              onClick={() => setMobileMega(mobileMega === 'product' ? null : 'product')}
            >
              Product
              <ChevronDown className={cn('h-4 w-4', mobileMega === 'product' && 'rotate-180')} />
            </button>
            {mobileMega === 'product' && (
              <div className="ml-2 space-y-3 border-l border-zinc-700 pl-3">
                {MARKETING_PRODUCT_MEGA_COLUMNS.map((col) => (
                  <div key={col.heading}>
                    <p className="text-[10px] font-bold uppercase tracking-widest text-zinc-500">{col.heading}</p>
                    {col.links.map((l) => (
                      <Link
                        key={l.label + l.to}
                        to={l.to}
                        className="block py-2 text-sm text-zinc-400"
                        onClick={() => setOpen(false)}
                      >
                        {l.label}
                      </Link>
                    ))}
                  </div>
                ))}
              </div>
            )}
            {MARKETING_PRIMARY_NAV.filter((i) => !i.mega).map((item) => (
              <Link
                key={item.id}
                to={item.to!}
                className={cn('rounded-lg px-3 py-2.5 text-sm font-medium', darkNav && 'text-zinc-200')}
                onClick={() => setOpen(false)}
              >
                {item.label}
              </Link>
            ))}
            <button
              type="button"
              className={cn(
                'flex w-full items-center justify-between rounded-lg px-3 py-2.5 text-sm font-medium',
                darkNav && 'text-zinc-200',
              )}
              onClick={() => setMobileMega(mobileMega === 'company' ? null : 'company')}
            >
              Company
              <ChevronDown className={cn('h-4 w-4', mobileMega === 'company' && 'rotate-180')} />
            </button>
            {mobileMega === 'company' && (
              <div className="ml-2 space-y-1 border-l border-zinc-700 pl-3">
                {MARKETING_COMPANY_LINKS.map((l) => (
                  <Link
                    key={l.to}
                    to={l.to}
                    className="block py-2 text-sm text-zinc-400"
                    onClick={() => setOpen(false)}
                  >
                    {l.label}
                  </Link>
                ))}
              </div>
            )}
            <Link
              to="/login"
              className={cn('mt-2 px-3 py-2.5 text-sm font-medium', darkNav && 'text-zinc-200')}
              onClick={() => setOpen(false)}
            >
              Sign in
            </Link>
            <Link to="/register" className="mt-1" onClick={() => setOpen(false)}>
              <Button variant="accent" type="button" className="w-full">
                {MARKETING_CTA_TRIAL}
              </Button>
            </Link>
          </div>
        </nav>
      )}
    </header>
  )
}
