-- Allow anonymous read of active subscription catalog (public pricing page only).

CREATE POLICY subscriptions_read_anon ON public.subscriptions
  FOR SELECT TO anon
  USING (is_active = true);
