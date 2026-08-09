import { X, Check } from 'lucide-react'
import { RiderPhonePreview } from '@/components/marketing/hero/RiderPhonePreview'

const OLD = [
  'Too many calls and chats',
  'Riders hard to reach',
  'Cash hard to track',
  'Customers left in the dark',
]

const NEW = [
  'One live operations center',
  'Every rider connected',
  'Every payment recorded',
  'Every customer updated',
]

const RIDER_IMG = '/marketing/delivery-rider.png'

export function OldVsDeliveryOS() {
  return (
    <section className="relative bg-[#11110F] py-16 sm:py-20 lg:py-24">
      <div className="mx-auto grid max-w-[1440px] gap-10 px-4 sm:px-6 lg:grid-cols-12 lg:items-center lg:gap-8 lg:px-8">
        <div className="grid gap-8 sm:grid-cols-2 lg:col-span-5">
          <div>
            <h3 className="text-xs font-bold uppercase tracking-widest text-red-500">The old way</h3>
            <ul className="mt-4 space-y-3">
              {OLD.map((t) => (
                <li key={t} className="flex gap-2 text-sm text-zinc-400">
                  <X className="h-4 w-4 shrink-0 text-red-500" aria-hidden />
                  {t}
                </li>
              ))}
            </ul>
          </div>
          <div>
            <h3 className="text-xs font-bold uppercase tracking-widest text-emerald-500">The DeliveryOS way</h3>
            <ul className="mt-4 space-y-3">
              {NEW.map((t) => (
                <li key={t} className="flex gap-2 text-sm text-zinc-300">
                  <Check className="h-4 w-4 shrink-0 text-emerald-500" aria-hidden />
                  {t}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="lg:col-span-3">
          <h2 className="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Delivery
            <span className="block">
              <span className="text-[#FFCB05]">should be simple.</span>
            </span>
          </h2>
          <p className="mt-4 text-sm leading-relaxed text-zinc-400 sm:text-base">
            We take the chaos out of deliveries so you can focus on growing your business.
          </p>
        </div>

        <div className="flex flex-col items-center gap-6 sm:flex-row lg:col-span-4 lg:justify-end">
          <RiderPhonePreview />
          <img
            src={RIDER_IMG}
            alt=""
            className="h-48 w-full max-w-[220px] rounded-2xl object-cover object-center shadow-xl sm:h-56 sm:max-w-[260px]"
            width={260}
            height={320}
            loading="lazy"
          />
        </div>
      </div>
    </section>
  )
}
