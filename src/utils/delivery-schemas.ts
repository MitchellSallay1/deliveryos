import { z } from 'zod'

export const deliveryStatusSchema = z.enum([
  'pending',
  'assigned',
  'accepted',
  'picked_up',
  'in_transit',
  'delivered',
  'failed',
  'cancelled',
])

export type DeliveryStatus = z.infer<typeof deliveryStatusSchema>

export const createDeliverySchema = z.object({
  pickupBusinessName: z.string().min(1, 'Pickup business is required'),
  pickupAddress: z.string().min(1, 'Pickup address is required'),
  customerName: z.string().min(1, 'Customer name is required'),
  customerPhone: z.string().min(7, 'Customer phone is required'),
  destinationAddress: z.string().min(1, 'Destination is required'),
  packageDescription: z.string().optional(),
  amountToCollectLrd: z.coerce.number().min(0).default(0),
  deliveryFeeLrd: z.coerce.number().min(0).default(500),
  customerId: z.string().uuid().optional(),
  deliveryZoneId: z.string().uuid().optional(),
  feeManualOverride: z.boolean().optional(),
})

export type CreateDeliveryInput = z.infer<typeof createDeliverySchema>

export const NEXT_STATUS: Partial<Record<DeliveryStatus, DeliveryStatus[]>> = {
  assigned: ['accepted', 'cancelled'],
  accepted: ['picked_up', 'failed', 'cancelled'],
  picked_up: ['in_transit', 'failed'],
  in_transit: ['delivered', 'failed'],
}

export function statusLabel(status: string) {
  return status.replaceAll('_', ' ')
}

export function formatLrd(amount: number) {
  return `${amount.toLocaleString()} LRD`
}

export function formatLrdFromCents(cents: number) {
  return formatLrd(cents / 100)
}
