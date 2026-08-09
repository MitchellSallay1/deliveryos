/**
 * Provider-neutral USSD rider endpoint.
 *
 * Normalized request body:
 * { phone, session_id, network?, input?, service_code? }
 *
 * Adapters (configure at reverse proxy or extend here):
 * - MTN Liberia: map MSISDN + sessionId + subscriberInput fields
 * - Orange Liberia: map analogous fields from aggregator webhook
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { carrierAuthErrorResponse, verifySharedSecret } from "../_shared/carrier-auth.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-ussd-secret",
};

type NormalizedUssdRequest = {
  phone: string;
  session_id: string;
  network?: string;
  input?: string;
  service_code?: string;
};

function normalizePayload(raw: Record<string, unknown>): NormalizedUssdRequest {
  return {
    phone: String(raw.phone ?? raw.msisdn ?? raw.msisdnNumber ?? ""),
    session_id: String(raw.session_id ?? raw.sessionId ?? raw.sessionID ?? ""),
    network: raw.network != null ? String(raw.network) : undefined,
    input: String(raw.input ?? raw.text ?? raw.subscriberInput ?? ""),
    service_code:
      raw.service_code != null ? String(raw.service_code) : undefined,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const auth = verifySharedSecret(req, "USSD_WEBHOOK_SECRET", "x-ussd-secret");
  if (!auth.ok) {
    return carrierAuthErrorResponse(auth, cors);
  }

  let body: Record<string, unknown> = {};
  const contentType = req.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    body = await req.json();
  } else {
    const form = await req.formData();
    for (const [k, v] of form.entries()) {
      body[k] = v;
    }
  }

  const normalized = normalizePayload(body);
  if (!normalized.phone || !normalized.session_id) {
    return new Response(
      JSON.stringify({ error: "phone and session_id required" }),
      { status: 400, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("handle_ussd_request", {
    p_phone: normalized.phone,
    p_session_id: normalized.session_id,
    p_text: normalized.input ?? "",
    p_network: normalized.network ?? null,
  });

  if (error) {
    return new Response(
      JSON.stringify({
        continue_session: false,
        message: "Service unavailable.",
      }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const response = {
    continue_session: Boolean(data?.continue_session),
    message: String(data?.message ?? ""),
  };

  return new Response(JSON.stringify(response), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
