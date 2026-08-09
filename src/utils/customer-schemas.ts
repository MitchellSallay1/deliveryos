import { z } from 'zod'

export const customerSchema = z.object({
  fullName: z.string().min(2, 'Name is required'),
  phone: z.string().min(7, 'Phone is required'),
  address: z.string().optional(),
  landmark: z.string().optional(),
  notes: z.string().optional(),
})

export type CustomerInput = z.infer<typeof customerSchema>
