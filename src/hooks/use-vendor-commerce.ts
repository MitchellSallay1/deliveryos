import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase/client'
import {
  adjustProductStock,
  deleteProductImage,
  fetchProductCategories,
  fetchStoreProfile,
  fetchVendorBranches,
  fetchVendorOrders,
  fetchVendorOverview,
  fetchVendorProducts,
  submitStoreProfileForReview,
  upsertProduct,
  upsertProductCategory,
  upsertProductImage,
  upsertProductOption,
  upsertProductOptionGroup,
  upsertStoreProfile,
  upsertVendorBranch,
  vendorAcceptOrder,
  vendorMarkOrderPreparing,
  vendorMarkOrderReady,
  vendorRejectOrder,
} from '@/services/vendor-commerce-service'

export function useStoreProfile(companyId: string | null) {
  return useQuery({
    queryKey: ['vendor-store-profile', companyId],
    queryFn: () => fetchStoreProfile(companyId!),
    enabled: !!companyId,
  })
}

export function useVendorOverview(companyId: string | null) {
  return useQuery({
    queryKey: ['vendor-overview', companyId],
    queryFn: () => fetchVendorOverview(companyId!),
    enabled: !!companyId,
  })
}

export function useVendorStoreActions(companyId: string | null) {
  const qc = useQueryClient()
  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['vendor-store-profile', companyId] })
    void qc.invalidateQueries({ queryKey: ['vendor-overview', companyId] })
  }
  return {
    save: useMutation({ mutationFn: upsertStoreProfile, onSuccess: invalidate }),
    submitForReview: useMutation({
      mutationFn: () => submitStoreProfileForReview(companyId!),
      onSuccess: invalidate,
    }),
  }
}

export function useProductCategories(companyId: string | null) {
  return useQuery({
    queryKey: ['vendor-categories', companyId],
    queryFn: () => fetchProductCategories(companyId!),
    enabled: !!companyId,
  })
}

export function useUpsertProductCategory(companyId: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: upsertProductCategory,
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['vendor-categories', companyId] }),
  })
}

export function useVendorProducts(companyId: string | null) {
  return useQuery({
    queryKey: ['vendor-products', companyId],
    queryFn: () => fetchVendorProducts(companyId!),
    enabled: !!companyId,
  })
}

export function useVendorProductActions(companyId: string | null) {
  const qc = useQueryClient()
  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['vendor-products', companyId] })
    void qc.invalidateQueries({ queryKey: ['vendor-overview', companyId] })
  }
  return {
    saveProduct: useMutation({ mutationFn: upsertProduct, onSuccess: invalidate }),
    saveOptionGroup: useMutation({ mutationFn: upsertProductOptionGroup, onSuccess: invalidate }),
    saveOption: useMutation({ mutationFn: upsertProductOption, onSuccess: invalidate }),
    saveImage: useMutation({ mutationFn: upsertProductImage, onSuccess: invalidate }),
    removeImage: useMutation({ mutationFn: deleteProductImage, onSuccess: invalidate }),
    adjustStock: useMutation({
      mutationFn: ({ productId, delta, reason }: { productId: string; delta: number; reason?: string }) =>
        adjustProductStock(productId, delta, reason),
      onSuccess: invalidate,
    }),
  }
}

/**
 * New commerce_orders rows and fulfillment_status/payment_status changes for
 * this vendor arrive over the same postgres_changes pattern already used by
 * useDeliveries — no new realtime infrastructure. deliveries changes are
 * also watched (for the future delivery_status column shown per order) so
 * the inbox updates once Phase D links a real delivery to an order.
 */
export function useVendorOrders(companyId: string | null, statuses: string[] | null, page: number) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['vendor-orders', companyId, statuses, page],
    queryFn: () => fetchVendorOrders(companyId!, statuses, page),
    enabled: !!companyId,
  })

  useEffect(() => {
    if (!companyId) return

    const invalidate = () => {
      void queryClient.invalidateQueries({ queryKey: ['vendor-orders', companyId] })
      void queryClient.invalidateQueries({ queryKey: ['vendor-overview', companyId] })
    }

    const channel = supabase
      .channel(`vendor-commerce-orders:${companyId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'commerce_orders', filter: `vendor_company_id=eq.${companyId}` },
        invalidate,
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'deliveries', filter: `merchant_company_id=eq.${companyId}` },
        invalidate,
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [companyId, queryClient])

  return query
}

export function useVendorOrderActions(companyId: string | null) {
  const qc = useQueryClient()
  const invalidate = () => {
    void qc.invalidateQueries({ queryKey: ['vendor-orders', companyId] })
    void qc.invalidateQueries({ queryKey: ['vendor-overview', companyId] })
  }
  return {
    accept: useMutation({ mutationFn: vendorAcceptOrder, onSuccess: invalidate }),
    reject: useMutation({
      mutationFn: ({ orderId, reason }: { orderId: string; reason?: string }) => vendorRejectOrder(orderId, reason),
      onSuccess: invalidate,
    }),
    markPreparing: useMutation({ mutationFn: vendorMarkOrderPreparing, onSuccess: invalidate }),
    markReady: useMutation({ mutationFn: vendorMarkOrderReady, onSuccess: invalidate }),
  }
}

export function useVendorBranches(companyId: string | null) {
  return useQuery({
    queryKey: ['vendor-branches', companyId],
    queryFn: () => fetchVendorBranches(companyId!),
    enabled: !!companyId,
  })
}

export function useUpsertVendorBranch(companyId: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: upsertVendorBranch,
    onSuccess: () => void qc.invalidateQueries({ queryKey: ['vendor-branches', companyId] }),
  })
}
