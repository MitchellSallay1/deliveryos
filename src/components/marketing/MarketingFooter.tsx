import { Link } from 'react-router-dom'
import { PoweredByPartner } from '@/components/brand/BrandLogo'

const FOOTER = {
  Product: [
    { to: '/features', label: 'Features' },
    { to: '/pricing', label: 'Pricing' },
    { to: '/developers', label: 'Developers' },
    { to: '/security', label: 'Security' },
  ],
  Solutions: [
    { to: '/solutions', label: 'Overview' },
    { to: '/solutions#couriers', label: 'Delivery companies' },
    { to: '/solutions#merchants', label: 'Merchants' },
  ],
  Company: [
    { to: '/about', label: 'About' },
    { to: '/contact', label: 'Contact' },
    { to: '/status', label: 'Status' },
  ],
  Legal: [
    { to: '/terms', label: 'Terms' },
    { to: '/privacy', label: 'Privacy' },
  ],
}

export function MarketingFooter() {
  const year = new Date().getFullYear()

  return (
    <footer className="border-t border-zinc-200 bg-zinc-950 text-zinc-300">
      <div className="mx-auto grid max-w-7xl gap-12 px-4 py-16 sm:grid-cols-2 lg:grid-cols-4 sm:px-6 lg:px-8">
        {Object.entries(FOOTER).map(([heading, links]) => (
          <div key={heading}>
            <h3 className="text-xs font-semibold uppercase tracking-widest text-zinc-500">{heading}</h3>
            <ul className="mt-5 space-y-3">
              {links.map((l) => (
                <li key={l.to}>
                  <Link to={l.to} className="text-sm text-zinc-400 transition hover:text-white">
                    {l.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="border-t border-white/10 py-10 text-center">
        <p className="text-sm font-semibold text-white">DeliveryOS</p>
        <PoweredByPartner className="mt-2 [&_p]:text-zinc-500" />
        <p className="mt-4 text-xs text-zinc-600">© {year} DeliveryOS</p>
      </div>
    </footer>
  )
}
