import { z } from 'zod'
import { normalizePhoneE164, isValidLiberiaMobile } from '@/lib/phone'

export const phoneInputSchema = z
  .string()
  .min(7, 'Phone number is required')
  .refine((v) => isValidLiberiaMobile(normalizePhoneE164(v)), {
    message: 'Enter a valid Liberia mobile number',
  })

export const otpCodeSchema = z
  .string()
  .min(4, 'Enter the verification code')
  .max(8, 'Enter the verification code')

export type PhoneInputForm = z.infer<typeof phoneInputSchema>

const optionalEmail = z.union([z.string().email('Enter a valid email'), z.literal('')]).optional()

export const companyRegisterSchema = z.object({
  businessType: z.literal('logistics_provider'),
  companyName: z.string().min(2, 'Company name is required'),
  companyPhone: phoneInputSchema,
  companyEmail: optionalEmail,
  fullName: z.string().min(2, 'Your name is required'),
})

export type CompanyRegisterForm = z.infer<typeof companyRegisterSchema>

export const merchantRegisterSchema = z.object({
  businessType: z.literal('merchant'),
  companyName: z.string().min(2, 'Company name is required'),
  companyPhone: phoneInputSchema,
  companyEmail: optionalEmail,
  fullName: z.string().min(2, 'Your name is required'),
})

export type MerchantRegisterForm = z.infer<typeof merchantRegisterSchema>

export const riderRegisterSchema = z.object({
  fullName: z.string().min(2, 'Full name is required'),
})

export type RiderRegisterForm = z.infer<typeof riderRegisterSchema>

export const linkRiderSchema = z
  .object({
    riderCode: z.string().optional(),
    inviteCode: z.string().optional(),
  })
  .refine((d) => Boolean(d.riderCode?.trim() || d.inviteCode?.trim()), {
    message: 'Enter a rider ID or invite code',
  })

export type LinkRiderForm = z.infer<typeof linkRiderSchema>

export const setupWorkspaceSchema = z.object({
  companyName: z.string().min(2, 'Company name is required'),
  businessType: z.enum(['logistics_provider', 'merchant', 'hybrid']),
  companyPhone: z.string().optional(),
  companyEmail: optionalEmail,
})

export type SetupWorkspaceForm = z.infer<typeof setupWorkspaceSchema>

export const teamInvitePhoneSchema = z.object({
  phone: phoneInputSchema,
  role: z.enum(['dispatcher', 'support_staff', 'rider']),
})

export type TeamInvitePhoneForm = z.infer<typeof teamInvitePhoneSchema>
