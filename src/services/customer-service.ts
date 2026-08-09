import { supabase } from '@/lib/supabase/client'
import type { Customer } from '@/types/fleet'
import type { CustomerInput } from '@/utils/customer-schemas'

export async function listCustomersDetailed(companyId: string) {
  const { data, error } = await supabase
    .from('customers')
    .select('*')
    .eq('company_id', companyId)
    .order('full_name')

  if (error) throw error
  return (data ?? []) as Customer[]
}

export async function upsertCustomer(companyId: string, input: CustomerInput) {
  const { data, error } = await supabase
    .from('customers')
    .upsert(
      {
        company_id: companyId,
        full_name: input.fullName,
        phone: input.phone,
        address: input.address ?? null,
        landmark: input.landmark ?? null,
        notes: input.notes ?? null,
      },
      { onConflict: 'company_id,phone' },
    )
    .select()
    .single()

  if (error) throw error
  return data as Customer
}

export async function updateCustomer(customerId: string, input: CustomerInput) {
  const { data, error } = await supabase
    .from('customers')
    .update({
      full_name: input.fullName,
      phone: input.phone,
      address: input.address ?? null,
      landmark: input.landmark ?? null,
      notes: input.notes ?? null,
    })
    .eq('id', customerId)
    .select()
    .single()

  if (error) throw error
  return data as Customer
}
