/**
 * Provider-neutral outbound WhatsApp transport for Gupshup.
 *
 * Contract confirmed directly against Gupshup's current official docs
 * (docs.gupshup.io — the actively-maintained, LLM-indexed doc set, not a
 * third-party blog or the older console-docs.gupshup.io Enterprise API
 * reference, which documents a different/older endpoint shape):
 *
 *  - Send (session/free-form text): POST https://api.gupshup.io/wa/api/v1/msg
 *    https://docs.gupshup.io/reference/msg
 *  - Send (template/HSM):           POST https://api.gupshup.io/wa/api/v1/template/msg
 *    https://docs.gupshup.io/reference/sending-text-template
 *  - Both: header `apikey: <key>`, `Content-Type: application/x-www-form-urlencoded`
 *    (form-encoded body, NOT JSON) with fields `channel=whatsapp`,
 *    `source=<registered WA number, digits only>`, `destination=<recipient,
 *    digits only>`, `src.name=<Gupshup app name>`, and either `message`
 *    (JSON-encoded {type:"text", text}) or `template` (JSON-encoded
 *    {id, params: [...]}) as a form field whose VALUE is itself a JSON string.
 *  - Success response: HTTP 2xx with `{"status":"submitted"|"success","messageId":"..."}`.
 *    This means Gupshup ACCEPTED the request for delivery — not that the
 *    message was delivered or even sent to WhatsApp yet. Real delivery
 *    state (sent/delivered/read/failed) only ever arrives later via the
 *    message-event webhook (see whatsapp-webhook) — never inferred from
 *    this response.
 *
 * Gap acknowledged, not guessed around: Gupshup's publicly documented
 * webhook setup (docs.gupshup.io/docs/set-webhookcallback-url) offers no
 * custom-header, shared-secret, or signature mechanism for verifying a
 * webhook call genuinely came from Gupshup (unlike Meta's own WhatsApp
 * Cloud API, which supports X-Hub-Signature-256 — Gupshup as a BSP does not
 * appear to expose an equivalent to app-level customers per available
 * documentation as of this implementation). whatsapp-webhook therefore uses
 * a URL-embedded shared secret plus payload-shape/app-name validation
 * instead of inventing an HMAC scheme Gupshup doesn't support — see that
 * function's header comment and docs/WHATSAPP.md for the full threat model.
 *
 * Intentionally plain, dependency-free TypeScript (no `Deno.*` calls) so it
 * unit-tests under Node/vitest exactly like _shared/sms-provider.ts.
 */

export type GupshupTextMessage = {
  destination: string
  text: string
}

export type GupshupTemplateMessage = {
  destination: string
  templateId: string
  /** Ordered values substituted into the template's {{1}}, {{2}}, ... placeholders. */
  params: string[]
}

export type GupshupSendResult =
  | { ok: true; httpStatus: number; providerMessageId: string | null; providerResponseRaw: string }
  | { ok: false; httpStatus: number | null; error: string; providerResponseRaw?: string }

export type GupshupConfig = {
  apiKey: string
  /** Gupshup app name (src.name) — e.g. "DeliveryOS". Configured, never hardcoded, so an app rename doesn't require a code change. */
  appName: string
  /** Registered WhatsApp Business sender number, digits only (no leading +). Never hardcoded — see GUPSHUP_SOURCE_NUMBER. */
  sourceNumber: string
  /** Override for testing; defaults to the real Gupshup API host. */
  baseUrl?: string
  timeoutMs?: number
}

const DEFAULT_BASE_URL = 'https://api.gupshup.io'
const DEFAULT_TIMEOUT_MS = 8000
const RAW_RESPONSE_LOG_LIMIT = 500

interface GupshupSuccessBody {
  status?: string
  messageId?: string
}

async function readRawResponse(res: Response): Promise<string> {
  try {
    const text = await res.text()
    return text.length > RAW_RESPONSE_LOG_LIMIT ? `${text.slice(0, RAW_RESPONSE_LOG_LIMIT)}…` : text
  } catch {
    return ''
  }
}

function parseMessageId(raw: string): string | null {
  try {
    const parsed = JSON.parse(raw) as GupshupSuccessBody
    return typeof parsed.messageId === 'string' ? parsed.messageId : null
  } catch {
    return null
  }
}

export class GupshupProvider {
  constructor(private readonly config: GupshupConfig) {}

  async sendText(message: GupshupTextMessage): Promise<GupshupSendResult> {
    return this.post('/wa/api/v1/msg', {
      channel: 'whatsapp',
      source: this.config.sourceNumber,
      destination: message.destination,
      'src.name': this.config.appName,
      message: JSON.stringify({ type: 'text', text: message.text }),
    })
  }

  async sendTemplate(message: GupshupTemplateMessage): Promise<GupshupSendResult> {
    return this.post('/wa/api/v1/template/msg', {
      channel: 'whatsapp',
      source: this.config.sourceNumber,
      destination: message.destination,
      'src.name': this.config.appName,
      template: JSON.stringify({ id: message.templateId, params: message.params }),
    })
  }

  private async post(path: string, fields: Record<string, string>): Promise<GupshupSendResult> {
    const url = `${(this.config.baseUrl ?? DEFAULT_BASE_URL).replace(/\/$/, '')}${path}`
    const timeoutMs = this.config.timeoutMs ?? DEFAULT_TIMEOUT_MS
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)

    let res: Response
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: {
          apikey: this.config.apiKey,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams(fields).toString(),
        signal: controller.signal,
      })
    } catch (e) {
      if (e instanceof Error && e.name === 'AbortError') {
        return { ok: false, httpStatus: null, error: 'timeout' }
      }
      return { ok: false, httpStatus: null, error: e instanceof Error ? e.message : 'network_error' }
    } finally {
      clearTimeout(timer)
    }

    const raw = await readRawResponse(res)

    if (!res.ok) {
      return { ok: false, httpStatus: res.status, error: `provider HTTP ${res.status}`, providerResponseRaw: raw }
    }

    return { ok: true, httpStatus: res.status, providerMessageId: parseMessageId(raw), providerResponseRaw: raw }
  }
}

/**
 * Classifies a failed GupshupSendResult for retry policy (see whatsapp-dispatch).
 *  - 'rate_limited': provider says slow down — defer, don't burn an attempt the same way as a real failure.
 *  - 'permanent': recipient/template/validation problem a retry can never fix.
 *  - 'transient': network/timeout/5xx — worth retrying with backoff.
 */
export type GupshupFailureClass = 'transient' | 'permanent' | 'rate_limited'

export function classifyGupshupFailure(result: Extract<GupshupSendResult, { ok: false }>): GupshupFailureClass {
  if (result.httpStatus === 429) return 'rate_limited'
  if (result.httpStatus !== null && result.httpStatus >= 400 && result.httpStatus < 500) return 'permanent'
  return 'transient'
}
