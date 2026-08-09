import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("API_CORS_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-api-key, x-correlation-id",
};

const MAX_BODY_BYTES = 256 * 1024;

function correlationId(req: Request): string {
  return req.headers.get("x-correlation-id") ?? crypto.randomUUID();
}

function safeErrorMessage(raw: string): string {
  if (/SQLSTATE|duplicate key|violates|relation "/i.test(raw)) {
    return "Request could not be completed";
  }
  return raw;
}

type ApiError = { error: { code: string; message: string } };

function json(data: unknown, status = 200, extraHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json", ...extraHeaders },
  });
}

function err(code: string, message: string, status: number, extraHeaders: Record<string, string> = {}) {
  return json({ error: { code, message } } satisfies ApiError, status, extraHeaders);
}

const rateMap = new Map<string, { count: number; reset: number }>();
const RATE_LIMIT = 120;
const RATE_WINDOW_MS = 60_000;

function rateLimit(keyId: string): boolean {
  const now = Date.now();
  const row = rateMap.get(keyId) ?? { count: 0, reset: now + RATE_WINDOW_MS };
  if (now > row.reset) {
    row.count = 0;
    row.reset = now + RATE_WINDOW_MS;
  }
  row.count += 1;
  rateMap.set(keyId, row);
  return row.count <= RATE_LIMIT;
}

function hasPermission(perms: unknown, needed: string): boolean {
  if (!Array.isArray(perms)) return false;
  return perms.includes(needed) || perms.includes("*");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const corr = correlationId(req);
  const respondErr = (code: string, message: string, status: number) =>
    err(code, message, status, { "X-Correlation-Id": corr });

  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/api-v1\/?/, "").replace(/^\/functions\/v1\/api-v1\/?/, "");

  const apiKey = req.headers.get("x-api-key") ?? "";
  if (!apiKey) {
    return respondErr("unauthorized", "Missing X-API-Key header", 401);
  }

  if (req.method === "POST" || req.method === "PUT" || req.method === "PATCH") {
    const len = Number(req.headers.get("content-length") ?? "0");
    if (len > MAX_BODY_BYTES) {
      return respondErr("payload_too_large", "Request body too large", 413);
    }
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: authRow, error: authErr } = await supabase.rpc("verify_api_key", {
    p_api_key: apiKey,
  });

  if (authErr || !authRow) {
    await supabase.rpc("log_api_auth_event", {
      p_key_prefix: apiKey.slice(0, 12),
      p_company_id: null,
      p_success: false,
      p_error_code: "invalid_key",
    });
    return respondErr("unauthorized", "Invalid API key", 401);
  }

  const companyId = String(authRow.company_id);
  const keyId = String(authRow.key_id);
  const permissions = authRow.permissions;

  if (!rateLimit(keyId)) {
    return respondErr("rate_limited", "Too many requests", 429);
  }

  try {
    if (req.method === "POST" && (path === "v1/deliveries" || path === "")) {
      if (!hasPermission(permissions, "delivery:create")) {
        return respondErr("forbidden", "Missing delivery:create permission", 403);
      }
      const body = await req.json();
      const { data, error } = await supabase.rpc("create_delivery", {
        p_company_id: companyId,
        p_pickup_business_name: body.pickup_business_name,
        p_pickup_address: body.pickup_address,
        p_customer_name: body.customer_name,
        p_customer_phone: body.customer_phone,
        p_destination_address: body.destination_address,
        p_package_description: body.package_description ?? null,
        p_amount_to_collect_lrd_cents: body.amount_to_collect_lrd_cents ?? 0,
        p_delivery_fee_lrd_cents: body.delivery_fee_lrd_cents ?? 0,
        p_customer_id: body.customer_id ?? null,
        p_delivery_zone_id: body.delivery_zone_id ?? null,
        p_fee_manual_override: body.fee_manual_override ?? false,
      });
      if (error) return respondErr("invalid_request", safeErrorMessage(error.message), 400);
      return json({ delivery: data }, 201);
    }

    const deliveryMatch = path.match(/^v1\/deliveries\/([0-9a-f-]{36})$/i);
    if (req.method === "GET" && deliveryMatch) {
      if (!hasPermission(permissions, "delivery:read")) {
        return respondErr("forbidden", "Missing delivery:read permission", 403);
      }
      const id = deliveryMatch[1];
      const { data, error } = await supabase
        .from("deliveries")
        .select("*")
        .eq("id", id)
        .eq("company_id", companyId)
        .maybeSingle();
      if (error) return respondErr("server_error", error.message, 500);
      if (!data) return respondErr("not_found", "Delivery not found", 404);
      return json({ delivery: data });
    }

    const trackMatch = path.match(/^v1\/tracking\/([A-Z0-9-]+)$/i);
    if (req.method === "GET" && trackMatch) {
      if (!hasPermission(permissions, "tracking:read")) {
        return respondErr("forbidden", "Missing tracking:read permission", 403);
      }
      const code = trackMatch[1];
      const { data, error } = await supabase.rpc("get_public_delivery_tracking", {
        p_tracking_code: code,
      });
      if (error) return respondErr("server_error", error.message, 500);
      if (!data) return respondErr("not_found", "Tracking not found", 404);
      return json({ tracking: data });
    }

    if (req.method === "GET" && path === "v1/branches") {
      const { data, error } = await supabase.rpc("list_company_branches", {
        p_company_id: companyId,
      });
      if (error) return respondErr("server_error", error.message, 500);
      return json({ branches: data ?? [] });
    }

    if (req.method === "GET" && path === "v1/vehicles") {
      if (!hasPermission(permissions, "fleet:read")) {
        return respondErr("forbidden", "Missing fleet:read permission", 403);
      }
      const { data, error } = await supabase.rpc("list_vehicles_page", {
        p_company_id: companyId,
        p_search: null,
        p_limit: 50,
        p_offset: 0,
      });
      if (error) return respondErr("server_error", error.message, 500);
      return json(data);
    }

    if (req.method === "GET" && path === "v1/inventory/items") {
      if (!hasPermission(permissions, "inventory:read")) {
        return respondErr("forbidden", "Missing inventory:read permission", 403);
      }
      const { data, error } = await supabase
        .from("inventory_items")
        .select("id, sku, name, unit, reorder_threshold, is_active")
        .eq("company_id", companyId)
        .eq("is_active", true);
      if (error) return respondErr("server_error", error.message, 500);
      return json({ items: data ?? [] });
    }

    if (req.method === "POST" && path === "v1/delivery-requests") {
      if (!hasPermission(permissions, "marketplace:request:create")) {
        return respondErr("forbidden", "Missing marketplace:request:create permission", 403);
      }
      const body = await req.json();
      const { data, error } = await supabase.rpc("create_delivery_request", {
        p_payload: { ...body, merchant_company_id: companyId, status: "draft" },
      });
      if (error) return respondErr("invalid_request", safeErrorMessage(error.message), 400);
      if (body.publish) {
        await supabase.rpc("publish_delivery_request", {
          p_request_id: data.id,
          p_merchant_company_id: companyId,
        });
      }
      return json({ delivery_request: data }, 201);
    }

    if (req.method === "GET" && path === "v1/delivery-requests") {
      if (!hasPermission(permissions, "marketplace:request:read")) {
        return respondErr("forbidden", "Missing marketplace:request:read permission", 403);
      }
      const limit = Number(url.searchParams.get("limit") ?? "25");
      const offset = Number(url.searchParams.get("offset") ?? "0");
      const status = url.searchParams.get("status");
      const { data, error } = await supabase.rpc("list_delivery_requests_page", {
        p_merchant_company_id: companyId,
        p_status: status,
        p_limit: limit,
        p_offset: offset,
      });
      if (error) return respondErr("server_error", error.message, 500);
      return json(data);
    }

    const drMatch = path.match(/^v1\/delivery-requests\/([0-9a-f-]{36})$/i);
    if (req.method === "GET" && drMatch) {
      if (!hasPermission(permissions, "marketplace:request:read")) {
        return respondErr("forbidden", "Missing marketplace:request:read permission", 403);
      }
      const id = drMatch[1];
      const { data, error } = await supabase
        .from("delivery_requests")
        .select("*")
        .eq("id", id)
        .eq("merchant_company_id", companyId)
        .maybeSingle();
      if (error) return respondErr("server_error", error.message, 500);
      if (!data) return respondErr("not_found", "Delivery request not found", 404);
      return json({ delivery_request: data });
    }

    const drCancelMatch = path.match(/^v1\/delivery-requests\/([0-9a-f-]{36})\/cancel$/i);
    if (req.method === "POST" && drCancelMatch) {
      if (!hasPermission(permissions, "marketplace:request:create")) {
        return respondErr("forbidden", "Missing marketplace:request:create permission", 403);
      }
      const body = await req.json().catch(() => ({}));
      const { data, error } = await supabase.rpc("cancel_delivery_request", {
        p_request_id: drCancelMatch[1],
        p_merchant_company_id: companyId,
        p_reason: body.reason ?? null,
      });
      if (error) return respondErr("invalid_request", safeErrorMessage(error.message), 400);
      return json({ delivery_request: data });
    }

    if (req.method === "GET" && path === "v1/marketplace/jobs") {
      if (!hasPermission(permissions, "marketplace:job:read")) {
        return respondErr("forbidden", "Missing marketplace:job:read permission", 403);
      }
      const limit = Number(url.searchParams.get("limit") ?? "25");
      const offset = Number(url.searchParams.get("offset") ?? "0");
      const status = url.searchParams.get("status") ?? "pending";
      const { data, error } = await supabase.rpc("list_marketplace_jobs_page", {
        p_provider_company_id: companyId,
        p_status: status,
        p_limit: limit,
        p_offset: offset,
      });
      if (error) return respondErr("server_error", error.message, 500);
      return json(data);
    }

    const jobAcceptMatch = path.match(/^v1\/marketplace\/jobs\/([0-9a-f-]{36})\/accept$/i);
    if (req.method === "POST" && jobAcceptMatch) {
      if (!hasPermission(permissions, "marketplace:job:accept")) {
        return respondErr("forbidden", "Missing marketplace:job:accept permission", 403);
      }
      const offerId = jobAcceptMatch[1];
      const { data: offer, error: offerErr } = await supabase
        .from("delivery_offers")
        .select("id")
        .eq("id", offerId)
        .eq("provider_company_id", companyId)
        .maybeSingle();
      if (offerErr) return respondErr("server_error", offerErr.message, 500);
      if (!offer) return respondErr("not_found", "Job offer not found", 404);
      const { data, error } = await supabase.rpc("accept_marketplace_offer", {
        p_offer_id: offerId,
        p_provider_company_id: companyId,
      });
      if (error) return respondErr("invalid_request", safeErrorMessage(error.message), 400);
      return json(data);
    }

    return respondErr("not_found", "Unknown route", 404);
  } catch (e) {
    return respondErr("server_error", safeErrorMessage(e instanceof Error ? e.message : "Unexpected error"), 500);
  }
});
