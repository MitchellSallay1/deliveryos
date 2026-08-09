import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function hmacSha256(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: pending, error } = await supabase
    .from("webhook_deliveries")
    .select("id, webhook_endpoint_id, payload, attempt_count, webhook_endpoints(url, secret)")
    .in("status", ["pending", "failed"])
    .lte("next_retry_at", new Date().toISOString())
    .limit(25);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let delivered = 0;
  let failed = 0;

  for (const row of pending ?? []) {
    const ep = row.webhook_endpoints as { url: string; secret: string } | null;
    if (!ep?.url) continue;

    const body = JSON.stringify({
      ...row.payload,
      event: (row.payload as { event?: string })?.event,
      occurred_at: new Date().toISOString(),
      webhook_delivery_id: row.id,
    });
    const signature = await hmacSha256(ep.secret, body);
    const attempt = (row.attempt_count ?? 0) + 1;

    try {
      const res = await fetch(ep.url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-DeliveryOS-Signature": `sha256=${signature}`,
          "X-DeliveryOS-Event": String((row.payload as { event?: string })?.event ?? ""),
          "X-DeliveryOS-Timestamp": new Date().toISOString(),
        },
        body,
        signal: AbortSignal.timeout(15_000),
      });

      const preview = (await res.text()).slice(0, 500);

      if (res.ok) {
        await supabase
          .from("webhook_deliveries")
          .update({
            status: "delivered",
            attempt_count: attempt,
            delivered_at: new Date().toISOString(),
            last_error: null,
            response_status: res.status,
            response_body_preview: preview,
          })
          .eq("id", row.id);
        delivered += 1;
      } else {
        const next = attempt >= 5 ? "dead" : "failed";
        await supabase
          .from("webhook_deliveries")
          .update({
            status: next,
            attempt_count: attempt,
            last_error: `HTTP ${res.status}`,
            next_retry_at: new Date(Date.now() + attempt * 60_000).toISOString(),
            response_status: res.status,
            response_body_preview: preview,
          })
          .eq("id", row.id);
        failed += 1;
      }
    } catch (e) {
      const next = attempt >= 5 ? "dead" : "failed";
      await supabase
        .from("webhook_deliveries")
        .update({
          status: next,
          attempt_count: attempt,
          last_error: e instanceof Error ? e.message : "fetch failed",
          next_retry_at: new Date(Date.now() + attempt * 60_000).toISOString(),
        })
        .eq("id", row.id);
      failed += 1;
    }
  }

  return new Response(JSON.stringify({ processed: (pending ?? []).length, delivered, failed }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
