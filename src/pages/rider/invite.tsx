import { useEffect, useState } from 'react'
import { Link, Navigate, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { fetchRiderInvitePreview } from '@/services/rider-portal-service'

export function RiderInvitePage() {
  const { code = '' } = useParams()
  const [preview, setPreview] = useState<{
    company_name: string
    rider_code: string
    invite_code: string
  } | null>(null)
  const [missing, setMissing] = useState(false)

  useEffect(() => {
    if (!code) return
    void fetchRiderInvitePreview(code)
      .then((data) => {
        if (!data) setMissing(true)
        else setPreview(data)
      })
      .catch(() => setMissing(true))
  }, [code])

  if (!code) {
    return <Navigate to="/register/rider" replace />
  }

  const registerHref = `/register/rider?invite=${encodeURIComponent(code)}`

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--color-background)] p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Rider invite</CardTitle>
          <CardDescription>
            {missing && 'This invite link is invalid or expired.'}
            {preview && (
              <>
                Join <strong>{preview.company_name}</strong> as rider{' '}
                <strong>{preview.rider_code}</strong>.
              </>
            )}
            {!missing && !preview && 'Loading invite…'}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <Link to={registerHref}>
            <Button type="button" className="w-full">
              Register as rider
            </Button>
          </Link>
          <Link to={`/login?next=${encodeURIComponent('/link-rider')}`}>
            <Button type="button" variant="outline" className="w-full">
              I already have an account
            </Button>
          </Link>
        </CardContent>
      </Card>
    </div>
  )
}
