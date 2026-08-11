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

const PRODUCT_IMAGE_BUCKET = 'commerce-product-images'
const PRODUCT_IMAGE_MAX_BYTES = 5 * 1024 * 1024
const PRODUCT_IMAGE_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp']

export function validateProductImageFile(file: File): string | null {
  if (!PRODUCT_IMAGE_MIME_TYPES.includes(file.type)) {
    return 'Only JPEG, PNG, or WebP images are allowed.'
  }
  if (file.size > PRODUCT_IMAGE_MAX_BYTES) {
    return 'Image must be 5MB or smaller.'
  }
  return null
}

function productImagePath(companyId: string, productId: string, fileName: string) {
  const safe = fileName.replace(/[^a-zA-Z0-9._-]/g, '_')
  return `${companyId}/${productId}/${Date.now()}-${safe}`
}

// commerce-product-images is a PUBLIC bucket (unlike delivery-photos) —
// product photos are meant to be visible on the future public storefront,
// so a permanent public URL is used instead of a signed, expiring one.
export async function uploadProductImage(companyId: string, productId: string, file: File) {
  const validationError = validateProductImageFile(file)
  if (validationError) throw new Error(validationError)

  const path = productImagePath(companyId, productId, file.name)

  const { error: uploadError } = await supabase.storage
    .from(PRODUCT_IMAGE_BUCKET)
    .upload(path, file, { cacheControl: '3600', upsert: false })

  if (uploadError) throw uploadError

  return { path, publicUrl: productImagePublicUrl(path) }
}

export function productImagePublicUrl(storagePath: string) {
  const { data } = supabase.storage.from(PRODUCT_IMAGE_BUCKET).getPublicUrl(storagePath)
  return data.publicUrl
}

export async function removeProductImageFile(storagePath: string) {
  const { error } = await supabase.storage.from(PRODUCT_IMAGE_BUCKET).remove([storagePath])
  if (error) throw error
}
