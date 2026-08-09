import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { useUpdateCompanyRiderChannels } from '@/hooks/use-settings'

type Props = {
  companyId: string
  settings: {
    allow_smartphone_riders?: boolean
    allow_button_phone_riders?: boolean
    enable_rider_sms?: boolean
    enable_rider_ussd?: boolean
    require_otp_button_phone_delivery?: boolean
  }
}

export function RiderChannelSettingsSection({ companyId, settings }: Props) {
  const mutation = useUpdateCompanyRiderChannels(companyId)
  const [message, setMessage] = useState<string | null>(null)

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setMessage(null)
    const fd = new FormData(e.currentTarget)
    try {
      await mutation.mutateAsync({
        allow_smartphone_riders: fd.get('allow_smartphone_riders') === 'on',
        allow_button_phone_riders: fd.get('allow_button_phone_riders') === 'on',
        enable_rider_sms: fd.get('enable_rider_sms') === 'on',
        enable_rider_ussd: fd.get('enable_rider_ussd') === 'on',
        require_otp_button_phone_delivery: fd.get('require_otp_button_phone_delivery') === 'on',
      })
      setMessage('Rider channel settings saved.')
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Save failed')
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Rider channels</CardTitle>
        <CardDescription>
          Smartphone riders use the PWA. Button-phone riders use SMS/USSD with phone identity (no
          login).
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form className="space-y-3 text-sm" onSubmit={onSubmit}>
          <ToggleRow
            name="allow_smartphone_riders"
            label="Allow smartphone riders"
            defaultChecked={settings.allow_smartphone_riders ?? true}
          />
          <ToggleRow
            name="allow_button_phone_riders"
            label="Allow button-phone riders"
            defaultChecked={settings.allow_button_phone_riders ?? true}
          />
          <ToggleRow
            name="enable_rider_sms"
            label="Enable rider SMS commands"
            defaultChecked={settings.enable_rider_sms ?? true}
          />
          <ToggleRow
            name="enable_rider_ussd"
            label="Enable rider USSD menus"
            defaultChecked={settings.enable_rider_ussd ?? true}
          />
          <ToggleRow
            name="require_otp_button_phone_delivery"
            label="Require customer OTP for button-phone delivery"
            defaultChecked={settings.require_otp_button_phone_delivery ?? false}
          />
          {message && <p className="text-sm text-teal-700">{message}</p>}
          <Button type="submit" disabled={mutation.isPending}>
            Save rider channels
          </Button>
        </form>
      </CardContent>
    </Card>
  )
}

function ToggleRow({
  name,
  label,
  defaultChecked,
}: {
  name: string
  label: string
  defaultChecked: boolean
}) {
  return (
    <label className="flex items-center gap-2">
      <input type="checkbox" name={name} defaultChecked={defaultChecked} className="h-4 w-4" />
      <span>{label}</span>
    </label>
  )
}
