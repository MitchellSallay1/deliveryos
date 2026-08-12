import { supabase } from '@/lib/supabase/client'

export type PlatformSetting = {
  key: string
  value: string | null
  description: string | null
  updated_at: string
  updated_by: string | null
}

export async function fetchPlatformSettings(): Promise<PlatformSetting[]> {
  const { data, error } = await supabase.rpc('admin_list_platform_settings')
  if (error) throw error
  return (data as unknown as PlatformSetting[]) ?? []
}

export async function setPlatformSetting(key: string, value: string): Promise<PlatformSetting> {
  const { data, error } = await supabase.rpc('admin_set_platform_setting', { p_key: key, p_value: value })
  if (error) throw error
  return data as unknown as PlatformSetting
}
