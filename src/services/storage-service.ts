import { supabase } from '@/lib/supabase/client'

const BUCKET = 'delivery-photos'

export function deliveryPhotoPath(companyId: string, deliveryId: string, fileName: string) {
  const safe = fileName.replace(/[^a-zA-Z0-9._-]/g, '_')
  return `${companyId}/${deliveryId}/${Date.now()}-${safe}`
}

export async function uploadDeliveryPhoto(
  companyId: string,
  deliveryId: string,
  file: File,
) {
  const path = deliveryPhotoPath(companyId, deliveryId, file.name)

  const { error: uploadError } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { cacheControl: '3600', upsert: false })

  if (uploadError) throw uploadError

  const { data, error: rpcError } = await supabase.rpc('register_delivery_photo', {
    p_company_id: companyId,
    p_delivery_id: deliveryId,
    p_storage_path: path,
  })

  if (rpcError) throw rpcError
  return { path, record: data }
}

export async function listDeliveryPhotos(deliveryId: string) {
  const { data, error } = await supabase
    .from('delivery_photos')
    .select('id, storage_path, created_at')
    .eq('delivery_id', deliveryId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return data ?? []
}

export async function signedPhotoUrl(storagePath: string, expiresIn = 3600) {
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrl(storagePath, expiresIn)

  if (error) throw error
  return data.signedUrl
}
