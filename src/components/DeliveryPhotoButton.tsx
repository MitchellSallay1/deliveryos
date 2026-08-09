import { useRef, useState } from 'react'
import { Button } from '@/components/ui/Button'
import { signedPhotoUrl, uploadDeliveryPhoto } from '@/services/storage-service'

export function DeliveryPhotoButton({
  companyId,
  deliveryId,
}: {
  companyId: string
  deliveryId: string
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [preview, setPreview] = useState<string | null>(null)

  async function onFile(file: File) {
    setBusy(true)
    setError(null)
    try {
      const { path } = await uploadDeliveryPhoto(companyId, deliveryId, file)
      const url = await signedPhotoUrl(path)
      setPreview(url)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="mt-1">
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
      <Button
        type="button"
        size="sm"
        variant="outline"
        disabled={busy}
        onClick={() => inputRef.current?.click()}
      >
        {busy ? 'Uploading…' : 'Photo'}
      </Button>
      {error && <p className="text-xs text-red-600">{error}</p>}
      {preview && (
        <a href={preview} target="_blank" rel="noreferrer" className="mt-1 block">
          <img src={preview} alt="Proof" className="mt-1 h-12 w-12 rounded object-cover" />
        </a>
      )}
    </div>
  )
}
