import { z } from 'zod'

export const riderStatusSchema = z.enum(['available', 'busy', 'offline', 'suspended'])

export const riderAccessModeSchema = z.enum(['smartphone', 'button_phone', 'both'])

export type RiderAccessMode = z.infer<typeof riderAccessModeSchema>

export const createRiderSchema = z.object({
  riderCode: z
    .string()
    .min(2, 'Rider ID is required')
    .max(16)
    .regex(/^[A-Za-z0-9_-]+$/, 'Use letters, numbers, - or _'),
  fullName: z.string().min(2, 'Full name is required'),
  phone: z.string().min(7, 'Phone is required'),
  status: riderStatusSchema.default('offline'),
  accessMode: riderAccessModeSchema.default('smartphone'),
  smsChannelEnabled: z.boolean().default(true),
  ussdChannelEnabled: z.boolean().default(true),
})

export type CreateRiderInput = z.infer<typeof createRiderSchema>

export const updateRiderStatusSchema = z.object({
  id: z.string().uuid(),
  status: riderStatusSchema,
})

export type UpdateRiderStatusInput = z.infer<typeof updateRiderStatusSchema>

export function riderStatusLabel(status: string) {
  return status.replaceAll('_', ' ')
}

export function riderAccessModeLabel(mode: string) {
  switch (mode) {
    case 'button_phone':
      return 'Button phone'
    case 'both':
      return 'Both'
    default:
      return 'Smartphone'
  }
}

export function isButtonPhoneCapable(mode: string) {
  return mode === 'button_phone' || mode === 'both'
}

/** Last 4 chars of tracking code (matches DB tracking_suffix). */
export function trackingCommandSuffix(trackingCode: string) {
  const compact = trackingCode.replace(/[^A-Za-z0-9]/g, '')
  return compact.slice(-4).toUpperCase()
}

/** Parse rider SMS command lines like "A 69B9" or "D 69B9 4821". */
export function parseRiderSmsCommand(text: string) {
  const parts = text.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return null
  const command = parts[0]![0]?.toUpperCase()
  if (!command || !'APTFD'.includes(command)) return null
  const suffix = parts[1]?.length === 4 ? parts[1].toUpperCase() : undefined
  const extra = parts[suffix ? 2 : 1]
  return { command, suffix, extra }
}
