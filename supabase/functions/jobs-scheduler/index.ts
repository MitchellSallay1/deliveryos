import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const secret = Deno.env.get("CRON_SECRET");
  if (secret) {
    const provided = req.headers.get("x-cron-secret");
    if (provided !== secret) {
      return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401, headers: cors });
    }
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("run_scheduled_maintenance_jobs");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: cors });
  }

  const base = Deno.env.get("SUPABASE_URL")!.replace(/\/$/, "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const dispatchHeaders: Record<string, string> = {
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
  if (secret) dispatchHeaders["x-cron-secret"] = secret;

  const [smsRes, webhookRes, emailRes] = await Promise.all([
    fetch(`${base}/functions/v1/sms-dispatch`, { method: "POST", headers: dispatchHeaders }),
    fetch(`${base}/functions/v1/webhooks-dispatch`, { method: "POST", headers: dispatchHeaders }),
    fetch(`${base}/functions/v1/email-dispatch`, { method: "POST", headers: dispatchHeaders }),
  ]);

  const sms = await smsRes.json().catch(() => ({}));
  const webhooks = await webhookRes.json().catch(() => ({}));
  const email = await emailRes.json().catch(() => ({}));

  return new Response(
    JSON.stringify({ maintenance: data, sms, webhooks, email, ran_at: new Date().toISOString() }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
