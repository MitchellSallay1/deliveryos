-- DeliveryOS · Storage bucket for proof-of-delivery photos

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'delivery-photos',
  'delivery-photos',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.storage_company_from_path(p_name TEXT)
RETURNS UUID
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF((string_to_array(p_name, '/'))[1], '')::UUID;
$$;

CREATE POLICY delivery_photos_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'delivery-photos'
    AND public.storage_company_from_path(name) IN (SELECT public.user_company_ids())
    AND public.has_company_role(
      public.storage_company_from_path(name),
      ARRAY['company_owner', 'dispatcher', 'rider']::public.company_role[]
    )
  );

CREATE POLICY delivery_photos_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'delivery-photos'
    AND (
      public.is_super_admin()
      OR public.storage_company_from_path(name) IN (SELECT public.user_company_ids())
    )
  );

CREATE OR REPLACE FUNCTION public.register_delivery_photo(
  p_company_id UUID,
  p_delivery_id UUID,
  p_storage_path TEXT
)
RETURNS public.delivery_photos
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.delivery_photos;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT (
    public.is_super_admin()
    OR public.has_company_role(
      p_company_id,
      ARRAY['company_owner', 'dispatcher', 'rider']::public.company_role[]
    )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.deliveries d
    WHERE d.id = p_delivery_id AND d.company_id = p_company_id
  ) THEN
    RAISE EXCEPTION 'delivery not found';
  END IF;

  INSERT INTO public.delivery_photos (company_id, delivery_id, storage_path, uploaded_by)
  VALUES (p_company_id, p_delivery_id, p_storage_path, auth.uid())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_delivery_photo TO authenticated;

CREATE OR REPLACE FUNCTION public.get_platform_analytics()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_super_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN jsonb_build_object(
    'companies_total', (SELECT COUNT(*)::INT FROM public.companies),
    'companies_active', (SELECT COUNT(*)::INT FROM public.companies WHERE status = 'active'),
    'companies_pending', (SELECT COUNT(*)::INT FROM public.companies WHERE status = 'pending'),
    'deliveries_today', (
      SELECT COUNT(*)::INT FROM public.deliveries
      WHERE created_at >= date_trunc('day', (current_timestamp AT TIME ZONE 'Africa/Monrovia'))
    ),
    'sms_sent', (SELECT COUNT(*)::INT FROM public.sms_logs WHERE direction = 'outbound')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_analytics TO authenticated;
