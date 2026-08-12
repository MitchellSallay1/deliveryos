import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import { AppRoutes } from '@/App'
import { AuthProvider } from '@/hooks/use-auth'
import { BrandingProvider } from '@/branding/BrandingProvider'
import { PwaInstallProvider } from '@/hooks/use-pwa-install'
import { NetworkStatusBanner } from '@/components/pwa/NetworkStatusBanner'
import { UpdateToast } from '@/components/pwa/UpdateToast'
import { InstallPromotionBanner } from '@/components/pwa/InstallPromotionBanner'
import '@/index.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrandingProvider>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <PwaInstallProvider>
            <AuthProvider>
              <NetworkStatusBanner />
              <AppRoutes />
              <UpdateToast />
              <InstallPromotionBanner />
            </AuthProvider>
          </PwaInstallProvider>
        </BrowserRouter>
      </QueryClientProvider>
    </BrandingProvider>
  </StrictMode>,
)
