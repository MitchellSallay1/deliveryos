import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase/client'
import { useAuthContext } from '@/hooks/use-auth-context'
import type { AuthContext } from '@/types/database'

type AuthState = {
  session: Session | null
  user: User | null
  loading: boolean
  context: AuthContext | null
  contextLoading: boolean
  signOut: () => Promise<void>
  refreshContext: () => void
}

const AuthCtx = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  const {
    data: context,
    isLoading: contextLoading,
    refetch,
  } = useAuthContext(user?.id)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setUser(data.session?.user ?? null)
      setLoading(false)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      setUser(nextSession?.user ?? null)
      setLoading(false)
    })

    return () => subscription.unsubscribe()
  }, [])

  const value = useMemo<AuthState>(
    () => ({
      session,
      user,
      loading,
      context: context ?? null,
      contextLoading,
      signOut: async () => {
        await supabase.auth.signOut()
        localStorage.removeItem('deliveryos_active_company_id')
      },
      refreshContext: () => {
        void refetch()
      },
    }),
    [session, user, loading, context, contextLoading, refetch],
  )

  return <AuthCtx.Provider value={value}>{children}</AuthCtx.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthCtx)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
