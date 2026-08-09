import { Outlet } from 'react-router-dom'
import { BrandLogo, PoweredByPartner } from '@/components/brand/BrandLogo'

export function AuthLayout() {
  return (
    <div className="flex min-h-screen flex-col bg-gradient-to-b from-zinc-100 to-[var(--color-background)]">
      <header className="flex items-center justify-between px-6 py-5">
        <BrandLogo />
      </header>
      <div className="flex flex-1 items-center justify-center p-4 pb-10">
        <div className="w-full max-w-md animate-fade-in">
          <Outlet />
        </div>
      </div>
      <footer className="pb-6">
        <PoweredByPartner />
      </footer>
    </div>
  )
}
