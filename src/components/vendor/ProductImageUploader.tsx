import { useRef, useState } from 'react'
import { Button } from '@/components/ui/Button'
import { productImagePublicUrl, uploadProductImage, validateProductImageFile } from '@/services/storage-service'
import type { ProductImage } from '@/services/vendor-commerce-service'

export function ProductImageUploader({
  companyId,
  productId,
  images,
  onUpload,
  onRemove,
  uploading,
  removingId,
}: {
  companyId: string
  productId: string
  images: ProductImage[]
  onUpload: (args: { storage_path: string; sort_order: number }) => Promise<unknown>
  onRemove: (image: ProductImage) => Promise<unknown>
  uploading: boolean
  removingId: string | null
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [error, setError] = useState<string | null>(null)

  async function onFile(file: File) {
    setError(null)
    const validationError = validateProductImageFile(file)
    if (validationError) {
      setError(validationError)
      return
    }
    try {
      const { path } = await uploadProductImage(companyId, productId, file)
      const nextSortOrder = images.reduce((max, img) => Math.max(max, img.sort_order), -1) + 1
      await onUpload({ storage_path: path, sort_order: nextSortOrder })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload failed')
    } finally {
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  const ordered = [...images].sort((a, b) => a.sort_order - b.sort_order)

  return (
    <div>
      <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-[var(--color-muted)]">Images</p>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      {ordered.length > 0 && (
        <ul className="mb-2 flex flex-wrap gap-3">
          {ordered.map((img) => (
            <li key={img.id} className="relative">
              <img
                src={productImagePublicUrl(img.storage_path)}
                alt="Product"
                className="h-20 w-20 rounded-lg border object-cover"
              />
              <Button
                type="button"
                size="sm"
                variant="outline"
                className="absolute -right-2 -top-2 h-6 w-6 rounded-full bg-white p-0 text-xs"
                disabled={removingId === img.id}
                onClick={() => void onRemove(img)}
                aria-label="Remove image"
              >
                {removingId === img.id ? '…' : '×'}
              </Button>
            </li>
          ))}
        </ul>
      )}
      {ordered.length === 0 && <p className="mb-2 text-sm text-[var(--color-muted)]">No images yet.</p>}

      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0]
          if (f) void onFile(f)
        }}
      />
      <Button type="button" size="sm" variant="outline" disabled={uploading} onClick={() => inputRef.current?.click()}>
        {uploading ? 'Uploading…' : 'Add image'}
      </Button>
      <p className="mt-1 text-xs text-[var(--color-muted)]">JPEG, PNG, or WebP, up to 5MB. Images are shown in upload order.</p>
    </div>
  )
}
