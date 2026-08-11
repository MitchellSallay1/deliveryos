import { useQuery } from '@tanstack/react-query'
import { fetchPublicStoreCatalog } from '@/services/storefront-service'

export function usePublicStoreCatalog(slug: string | undefined) {
  return useQuery({
    queryKey: ['public-store-catalog', slug],
    queryFn: () => fetchPublicStoreCatalog(slug!),
    enabled: !!slug,
    staleTime: 30_000,
  })
}
