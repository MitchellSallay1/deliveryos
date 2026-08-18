import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  WinAggregatorMtnProvider,
  normalizeMtnCollectionResult,
  validateMtnMsisdn,
} from "../_shared/winaggregator-mtn-provider.ts";

/**
 * Customer-facing entry point for MTN MoMo collection on a Commerce order.
 * PRODUCTION FINANCIAL CODE — see docs/MTN_MOMO_PAYMENTS.md.
 *
 * Deliberately NOT deployed with --no-verify-jwt: this is a real, signed-in-
 * customer action, unlike the internal webhook/cron functions elsewhere in
 * this repo. Supabase's gateway verifies the JWT before this code runs; the
 * Authorization header is then forwarded to a USER-SCOPED Supabase client
 * so initiate_commerce_order_mtn_payment runs as that user under normal
 * RLS/auth.uid() semantics — this function does not decide who is allowed
 * to pay for what; the RPC's own authorization checks do (see the
 * migration).
 *
 * Two-phase, not one 70-75s synchronous call — see the migration header
 * "WHY A FIRE-THEN-BACKGROUND-POLL DESIGN":
 *   Phase 1 (synchronous, sub-second): validate + lock + create the
 *   attempt + mark it 'requesting'. Returns to the browser immediately.
 *   Phase 2 (EdgeRuntime.waitUntil, up to ~75s): the actual provider call,
 *   normalized, recorded via record_payment_attempt_result. The browser
 *   never holds a connection open for this — it polls/subscribes to the
 *   payment_attempts row instead (RLS already grants the paying customer
 *   read access — see the migration's payment_attempts_select policy).
 */

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

// Maps the RPC's stable error codes (RAISE EXCEPTION '<code>') to an HTTP
// status and a client-safe message — never the raw Postgres error text.
const ERROR_MAP: Record<string, { status: number; message: string }> = {
  "not authenticated": { status: 401, message: "Sign in required." },
  order_not_found: { status: 404, message: "Order not found." },
  forbidden: { status: 403, message: "This order does not belong to you." },
  order_not_mtn_momo: { status: 409, message: "This order was not placed with MTN MoMo as the payment method." },
  order_not_payable: { status: 409, message: "This order is not awaiting payment." },
  commerce_not_enabled: { status: 409, message: "This store cannot currently accept payments." },
  mtn_momo_collections_disabled: { status: 503, message: "MTN MoMo collection is currently unavailable." },
  invalid_msisdn: { status: 400, message: "Enter a valid Liberian MTN MoMo number." },
  invalid_amount: { status: 409, message: "This order has no payable amount." },
  payment_already_in_progress: { status: 409, message: "A payment is already being processed for this order." },
};

function mapRpcError(message: string): { status: number; message: string } {
  for (const [code, mapped] of Object.entries(ERROR_MAP)) {
    if (message.includes(code)) return mapped;
  }
  return { status: 500, message: "Could not start payment. Please try again." };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const secretString = Deno.env.get("WINAGGREGATOR_MTN_SECRET_STRING");
  const companyName = Deno.env.get("WINAGGREGATOR_MTN_COMPANY_NAME");
  const baseUrl = Deno.env.get("WINAGGREGATOR_MTN_BASE_URL");

  if (!secretString || !companyName) {
    // Fail closed BEFORE creating any payment_attempts row — an attempt
    // that can never be processed is worse than no attempt at all. This is
    // INDEPENDENT of the mtn_momo_collections_enabled platform setting
    // (checked inside initiate_commerce_order_mtn_payment below, via
    // ERROR_MAP's mtn_momo_collections_disabled entry) — missing
    // credentials fail closed on their own even if a Super Admin has
    // activated the setting, and an activated setting with no credentials
    // still fails closed here regardless of what the RPC would have said.
    return jsonResponse(503, { error: "not_configured", message: "MTN MoMo collection is not yet configured." });
  }

  let body: { orderId?: string; msisdn?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "invalid_json" });
  }

  const orderId = typeof body.orderId === "string" ? body.orderId : null;
  const rawMsisdn = typeof body.msisdn === "string" ? body.msisdn : null;
  if (!orderId || !rawMsisdn) {
    return jsonResponse(400, { error: "invalid_request", message: "orderId and msisdn are required." });
  }

  // Server-side validation before it ever reaches the RPC or the provider —
  // the RPC re-validates independently (defense in depth), this is just an
  // early, cheap rejection for an obviously malformed number.
  const msisdnCheck = validateMtnMsisdn(rawMsisdn);
  if (!msisdnCheck.ok) {
    return jsonResponse(400, { error: "invalid_msisdn", message: "Enter a valid Liberian MTN MoMo number." });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(401, { error: "not_authenticated" });
  }

  // User-scoped client: initiate_commerce_order_mtn_payment runs AS this
  // user, so auth.uid()-based authorization inside it is the real user, not
  // service_role.
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: attempt, error: initiateError } = await userClient
    .rpc("initiate_commerce_order_mtn_payment", { p_order_id: orderId, p_msisdn: rawMsisdn })
    .single();

  if (initiateError || !attempt) {
    const mapped = mapRpcError(initiateError?.message ?? "");
    return jsonResponse(mapped.status, { error: "initiate_failed", message: mapped.message });
  }

  const attemptRow = attempt as { id: string; external_id: string; gross_amount_cents: number; currency: string };

  // Service-role client for everything past this point: the state
  // transition and provider call are system actions, not user actions.
  const serviceClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: markError } = await serviceClient.rpc("mark_payment_attempt_requesting", { p_attempt_id: attemptRow.id });
  if (markError) {
    // Extremely unlikely (we just created this attempt in 'created' state
    // moments ago) but if it happens, surface a clean 500 rather than
    // silently pretending the request phase started.
    return jsonResponse(500, { error: "requesting_failed", message: "Could not start the payment request." });
  }

  const runCollection = async () => {
    const provider = new WinAggregatorMtnProvider({
      baseUrl: baseUrl || undefined,
      secretString,
      companyName,
    });

    const raw = await provider.collect({
      amountCents: attemptRow.gross_amount_cents,
      currency: attemptRow.currency as "LRD" | "USD",
      externalId: attemptRow.external_id,
      msisdn: msisdnCheck.normalized,
    });

    const normalized = normalizeMtnCollectionResult(raw);

    const { error: resultError } = await serviceClient.rpc("record_payment_attempt_result", {
      p_attempt_id: attemptRow.id,
      p_state: normalized.state,
      p_raw_status: normalized.rawStatus,
      p_http_status: normalized.httpStatus,
      p_provider_reference_id: normalized.providerReferenceId,
      p_financial_transaction_id: normalized.financialTransactionId,
      p_provider_gross_cents: normalized.providerGrossCents,
      p_provider_fee_cents: normalized.providerFeeCents,
      p_provider_net_cents: normalized.providerNetCents,
      p_failure_category: normalized.failureCategory,
      p_error_message: normalized.errorMessage,
    });

    if (resultError) {
      // Never log secret_string, the full request, or the raw provider
      // body — only the failure class and attempt id.
      console.error("mtn-collect: failed to record result", { attemptId: attemptRow.id, error: resultError.message });
    }
  };

  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(runCollection());
  } else {
    // Local/dev fallback where EdgeRuntime isn't available.
    await runCollection();
  }

  return jsonResponse(202, {
    attemptId: attemptRow.id,
    externalId: attemptRow.external_id,
    state: "requesting",
  });
});
