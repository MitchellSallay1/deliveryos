import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { carrierAuthErrorResponse, verifySharedSecret } from "../_shared/carrier-auth.ts";
import { WinAggregatorSmsProvider } from "../_shared/sms-provider.ts";

const DEFAULT_WINAGGREGATOR_ENDPOINT = "https://winaggregator-mtn.com/request/sms-service/1";
const DEFAULT_WINAGGREGATOR_SENDER_ID = "DelivOS";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  // Internal-only: invoked by jobs-scheduler, which forwards CRON_SECRET.
  const auth = verifySharedSecret(req, "CRON_SECRET", "x-cron-secret");
  if (!auth.ok) {
    return carrierAuthErrorResponse(auth, cors);
  }

  const provider = Deno.env.get("SMS_PROVIDER") ?? "stub";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = new Date().toISOString();
  const { data: rows, error } = await supabase
    .from("sms_outbox")
    .select("id, company_id, phone, body, attempt_count")
    .in("status", ["pending", "failed"])
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${now}`)
    .order("created_at", { ascending: true })
    .limit(50);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: cors });
  }

  let sent = 0;
  let failed = 0;

  const winAggregator = provider === "winaggregator"
    ? new WinAggregatorSmsProvider({
      endpoint: Deno.env.get("WINAGGREGATOR_SMS_ENDPOINT") ?? DEFAULT_WINAGGREGATOR_ENDPOINT,
      senderId: Deno.env.get("WINAGGREGATOR_SENDER_ID") ?? DEFAULT_WINAGGREGATOR_SENDER_ID,
    })
    : null;

  for (const row of rows ?? []) {
    await supabase
      .from("sms_outbox")
      .update({ status: "processing", last_attempt_at: now })
      .eq("id", row.id);

    const attempt = (row.attempt_count ?? 0) + 1;
    try {
      if (provider === "stub") {
        await supabase
          .from("sms_outbox")
          .update({
            status: "sent",
            sent_at: now,
            provider: "stub",
            provider_message_id: `stub-${row.id}`,
            attempt_count: attempt,
          })
          .eq("id", row.id);
        sent += 1;
        continue;
      }

      if (provider === "winaggregator" && winAggregator) {
        const result = await winAggregator.send({ phone: row.phone, message: row.body });
        if (!result.ok) {
          const detail = result.providerResponseRaw ? `${result.error}: ${result.providerResponseRaw}` : result.error;
          throw new Error(detail);
        }

        await supabase
          .from("sms_outbox")
          .update({
            status: "sent",
            sent_at: now,
            provider: "winaggregator",
            attempt_count: attempt,
          })
          .eq("id", row.id);
        sent += 1;
        continue;
      }

      throw new Error(`Unknown SMS_PROVIDER: ${provider}`);
    } catch (e) {
      const dead = attempt >= 5;
      await supabase
        .from("sms_outbox")
        .update({
          status: dead ? "dead" : "failed",
          attempt_count: attempt,
          last_error: e instanceof Error ? e.message : "send failed",
          next_attempt_at: new Date(Date.now() + attempt * 60_000).toISOString(),
        })
        .eq("id", row.id);
      failed += 1;
    }
  }

  return new Response(JSON.stringify({ provider, sent, failed }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
