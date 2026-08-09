import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-sms-secret",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const secret = Deno.env.get("SMS_WEBHOOK_SECRET");
  if (secret && req.headers.get("x-sms-secret") !== secret) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let from = "";
  let text = "";

  const contentType = req.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    const body = await req.json();
    from = String(body.from ?? "");
    text = String(body.text ?? body.message ?? "");
  } else {
    const form = await req.formData();
    from = String(form.get("from") ?? "");
    text = String(form.get("text") ?? form.get("message") ?? "");
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase.rpc("process_inbound_sms", {
    p_phone: from,
    p_text: text,
  });

  if (error) {
    return new Response(JSON.stringify({ ok: false, message: "Could not process SMS." }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const result = data as {
    ok?: boolean;
    reply_message?: string;
    reply_phone?: string;
    company_id?: string;
  };

  if (result?.reply_message && result.reply_phone && result.company_id) {
    await supabase.rpc("queue_outbound_sms", {
      p_company_id: result.company_id,
      p_phone: result.reply_phone,
      p_body: result.reply_message,
      p_delivery_id: null,
    });
  }

  return new Response(JSON.stringify(data), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
