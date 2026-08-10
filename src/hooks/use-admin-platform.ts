import { useQuery } from '@tanstack/react-query'
import {
  adminGlobalSearch,
  adminSupportLookup,
  fetchAdminDeliveryDetail,
  fetchAdminMapPoints,
  fetchCommandCenter,
  fetchCommunicationsSummary,
  fetchCompany360,
  fetchExtendedHealthSnapshot,
  fetchLiveSnapshot,
  fetchNetworkMetrics,
  fetchPlatformAlerts,
  fetchPlatformSecuritySnapshot,
  fetchTrialFunnel,
  listAdminApiKeysPage,
  listAdminCompaniesPage,
  listAdminDeliveriesPage,
  listAuditLogsAdmin,
} from '@/services/admin-platform-service'

export function useCommandCenter(enabled = true) {
  return useQuery({
    queryKey: ['admin', 'command-center'],
    queryFn: fetchCommandCenter,
    enabled,
    refetchInterval: 60_000,
  })
}

export function useLiveSnapshot(enabled = true) {
  return useQuery({
    queryKey: ['admin', 'live'],
    queryFn: fetchLiveSnapshot,
    enabled,
    refetchInterval: 15_000,
  })
}

export function useNetworkMetrics(days: number, enabled = true) {
  return useQuery({
    queryKey: ['admin', 'network', days],
    queryFn: () => fetchNetworkMetrics(days),
    enabled,
  })
}

export function useTrialFunnel(enabled = true) {
  return useQuery({
    queryKey: ['admin', 'trial-funnel'],
    queryFn: fetchTrialFunnel,
    enabled,
  })
}

export function usePlatformAlerts(enabled = true) {
  return useQuery({
    queryKey: ['admin', 'alerts'],
    queryFn: fetchPlatformAlerts,
    enabled,
    refetchInterval: 60_000,
  })
}

export function useAdminCompaniesPage(
  params: Parameters<typeof listAdminCompaniesPage>[0],
  enabled = true,
) {
  return useQuery({
    queryKey: ['admin', 'companies-page', params],
    queryFn: () => listAdminCompaniesPage(params),
    enabled,
  })
}

export function useCompany360(companyId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['admin', 'company-360', companyId],
    queryFn: () => fetchCompany360(companyId!),
    enabled: enabled && !!companyId,
  })
}

export function useAdminDeliveriesPage(
  params: Parameters<typeof listAdminDeliveriesPage>[0],
  enabled = true,
) {
  return useQuery({
    queryKey: ['admin', 'deliveries', params],
    queryFn: () => listAdminDeliveriesPage(params),
    enabled,
  })
}

export function useAdminDeliveryDetail(id: string | undefined, enabled: boolean) {
  return useQuery({
    queryKey: ['admin', 'delivery', id],
    queryFn: () => fetchAdminDeliveryDetail(id!),
    enabled: enabled && !!id,
  })
}

export function useAdminMapPoints(companyId?: string, enabled = true) {
  return useQuery({
    queryKey: ['admin', 'map', companyId],
    queryFn: () => fetchAdminMapPoints(companyId),
    enabled,
    refetchInterval: 30_000,
  })
}

export function useCommunicationsSummary(days: number, enabled = true) {
  return useQuery({
    queryKey: ['admin', 'communications', days],
    queryFn: () => fetchCommunicationsSummary(days),
    enabled,
  })
}

export function useAdminApiKeysPage(
  params: Parameters<typeof listAdminApiKeysPage>[0],
  enabled = true,
) {
  return useQuery({
    queryKey: ['admin', 'api-keys', params],
    queryFn: () => listAdminApiKeysPage(params),
    enabled,
  })
}

export function useAdminGlobalSearch(query: string, enabled: boolean) {
  return useQuery({
    queryKey: ['admin', 'search', query],
    queryFn: () => adminGlobalSearch(query),
    enabled: enabled && query.trim().length >= 2,
  })
}

export function useSupportLookup(query: string, enabled: boolean) {
  return useQuery({
    queryKey: ['admin', 'support', query],
    queryFn: () => adminSupportLookup(query),
    enabled: enabled && query.trim().length >= 2,
  })
}

export function useAuditLogsAdmin(
  params: Parameters<typeof listAuditLogsAdmin>[0],
  enabled = true,
) {
  return useQuery({
    queryKey: ['admin', 'audit', params],
    queryFn: () => listAuditLogsAdmin(params),
    enabled,
  })
}

export function useExtendedHealth(enabled = true) {
  return useQuery({
    queryKey: ['admin', 'health-extended'],
    queryFn: fetchExtendedHealthSnapshot,
    enabled,
    refetchInterval: 60_000,
  })
}

export function useSecuritySnapshot(enabled = true) {
  return useQuery({
    queryKey: ['admin', 'security'],
    queryFn: fetchPlatformSecuritySnapshot,
    enabled,
    refetchInterval: 60_000,
  })
}
