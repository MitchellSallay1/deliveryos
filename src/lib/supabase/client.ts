import { createClient } from '@supabase/supabase-js'
import type { Database } from '@/types/supabase'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// Fail fast rather than silently falling back to a placeholder host: a
// placeholder client builds and deploys successfully but leaves every
// network call failing against a nonexistent origin, with only an
// easy-to-miss console warning as the signal. A loud throw at import time
// is the correct behavior for a build/deploy misconfiguration — this
// should never be reachable in a correctly configured environment (local
// dev via .env.local, production via hosting-provider env vars).
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'DeliveryOS: VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are required. ' +
      'Copy .env.example to .env.local for local development, or set them as ' +
      'build-time environment variables in your hosting provider for production.',
  )
}

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})
