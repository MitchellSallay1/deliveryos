import { Link, Outlet } from 'react-router-dom'
import '@/styles/marketing.css'
import { MarketingFooter } from '@/components/marketing/MarketingFooter'
import { MarketingHeader } from '@/components/marketing/MarketingHeader'

export function MarketingLayout() {
  return (
    <div className="mkt-root flex min-h-screen flex-col overflow-x-hidden">
      <MarketingHeader />
      <main className="flex-1">
        <Outlet />
      </main>
      <MarketingFooter />
    </div>
  )
}

export function MarketingPageShell({
  children,
  className = '',
}: {
  children: React.ReactNode
  className?: string
}) {
  return <div className={`mx-auto w-full max-w-7xl px-4 py-16 sm:px-6 lg:px-8 ${className}`}>{children}</div>
}

export function MarketingSection({
  title,
  subtitle,
  children,
  id,
  className = '',
}: {
  title: string
  subtitle?: string
  children: React.ReactNode
  id?: string
  className?: string
}) {
  return (
    <section id={id} className={`py-16 sm:py-20 ${className}`}>
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="max-w-2xl">
          <h2 className="text-3xl font-semibold tracking-tight text-zinc-900 sm:text-4xl">{title}</h2>
          {subtitle && <p className="mt-3 text-lg text-zinc-600">{subtitle}</p>}
        </div>
        <div className="mt-10">{children}</div>
      </div>
    </section>
  )
}

export function MarketingCtaBand() {
  return (
    <section className="mkt-section-dark py-16">
      <div className="mx-auto flex max-w-7xl flex-col items-start justify-between gap-6 px-4 sm:flex-row sm:items-center sm:px-6 lg:px-8">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">Start free for 7 days</h2>
          <p className="mt-2 text-zinc-400">Phone verification · No card required</p>
        </div>
        <Link
          to="/register"
          className="inline-flex h-11 items-center justify-center rounded-lg bg-[var(--color-accent)] px-6 text-sm font-semibold text-black transition hover:brightness-95"
        >
          Start free
        </Link>
      </div>
    </section>
  )
}
