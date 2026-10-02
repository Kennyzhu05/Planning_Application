import { ApiError, readJsonLimited } from "./http";
import { completionPayload } from "./prompts";
import { validateOutput } from "./validation";
import type { BreakdownInput, BreakdownOutput, ProviderDiagnostic } from "./types";

const GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions";
const REQUEST_TIMEOUT_MS = 35000;

// Only fixed identifiers may leave this module. Provider messages can contain
// submitted context, generated text, or credentials, so never echo or log them.
const SAFE_CODES = new Set([
  "invalid_api_key", "invalid_request_error", "authentication_error", "permission_error",
  "model_not_found", "model_decommissioned", "model_permission_blocked",
  "json_validate_failed", "json_schema_invalid", "invalid_json_schema", "generation_failed",
  "unsupported_parameter", "context_length_exceeded", "rate_limit_exceeded",
  "insufficient_quota", "server_error", "service_unavailable"
]);
const SAFE_PARAMETERS = new Set([
  "model", "messages", "messages.0.role", "messages.0.content", "messages.1.content",
  "max_completion_tokens", "response_format", "response_format.type",
  "response_format.json_schema", "response_format.json_schema.name",
  "response_format.json_schema.strict", "response_format.json_schema.schema",
  "reasoning_effort", "reasoning_format", "include_reasoning", "stream"
]);

export function configuredGroqKey(value: unknown): string {
  if (typeof value !== "string" || !value.trim())
    throw new ApiError(503, "PROVIDER_KEY_MISSING",
      "The server is missing its GROQ_API_KEY secret. Ask the project owner to configure it.");
  const key = value.trim();
  // Validate header-safe syntax, not the provider's key prefix or authenticity.
  if (!/^[A-Za-z0-9_-]{20,512}$/.test(key))
    throw new ApiError(503, "PROVIDER_KEY_FORMAT",
      "The server's Groq key has an invalid format. Re-enter only the key, without quotes or a Bearer prefix.");
  return key;
}

interface ProviderFailure {
  diagnostic: ProviderDiagnostic;
  reason?: "schema" | "model" | "generation";
}

async function providerFailure(response: Response, signal: AbortSignal): Promise<ProviderFailure> {
  const result: ProviderFailure = { diagnostic: { status: response.status } };
  try {
    const body = await readJsonLimited(response, 16384, 5000, signal) as {
      error?: { code?: unknown; type?: unknown; param?: unknown; message?: unknown };
    } | null;
    const detail = body?.error;
    for (const code of [detail?.code, detail?.type]) {
      if (typeof code === "string" && SAFE_CODES.has(code)) {
        result.diagnostic.code = code;
        break;
      }
    }
    if (typeof detail?.param === "string" && SAFE_PARAMETERS.has(detail.param))
      result.diagnostic.parameter = detail.param;

    // Classify known phrases into fixed explanations. The original text stays private.
    if (typeof detail?.message === "string") {
      if (/failed to generate|failed generation|json validation|json_validate_failed/i.test(detail.message))
        result.reason = "generation";
      else if (/json.schema|response_format|structured output|additionalproperties/i.test(detail.message))
        result.reason = "schema";
      else if (/model.*(?:does not exist|not found|decommissioned|not supported|not permitted|not allowed)/i.test(detail.message))
        result.reason = "model";
    }
  } catch {
    // HTML, oversized, empty, or slow error bodies must not hide the HTTP status.
  }
  return result;
}

function retryAfter(response: Response): number {
  const value = response.headers.get("Retry-After")?.trim();
  if (!value) return 60;
  const seconds = /^\d+(?:\.\d+)?$/.test(value)
    ? Number(value) : (Date.parse(value) - Date.now()) / 1000;
  return Number.isFinite(seconds) && seconds > 0 ? Math.min(86400, Math.ceil(seconds)) : 60;
}

function rejected(response: Response, failure: ProviderFailure): ApiError {
  const { diagnostic, reason } = failure;
  const code = diagnostic.code;
  const suffix = ` (Groq HTTP ${diagnostic.status}${code ? `; code: ${code}` : ""}`
    + `${diagnostic.parameter ? `; parameter: ${diagnostic.parameter}` : ""}).`;
  const error = (status: number, id: string, message: string, retry?: number) =>
    new ApiError(status, id, message + suffix, retry, diagnostic);

  if (response.status >= 300 && response.status < 400)
    return error(502, "PROVIDER_REDIRECT", "Groq returned an unexpected redirect. The server did not follow it");
  if (response.status === 401)
    return error(503, "PROVIDER_AUTHENTICATION", "Groq rejected the server API key. Ask the project owner to replace the GROQ_API_KEY secret");
  if (response.status === 403)
    return error(503, "PROVIDER_ACCESS_DENIED", "Groq denied access. Ask the project owner to check the key's project and model permissions");
  if (response.status === 429)
    return error(429, "PROVIDER_LIMIT", "Groq's usage limit was reached. Wait before trying again", retryAfter(response));
  if (response.status === 408 || response.status === 504)
    return error(504, "AI_TIMEOUT", "Groq timed out. Please try again later");
  if (response.status >= 500)
    return error(502, "PROVIDER_UNAVAILABLE", "Groq could not complete the request. Please try again later");
  if (code === "insufficient_quota")
    return error(503, "PROVIDER_QUOTA", "Groq's account allowance is unavailable. Ask the project owner to check provider usage");
  if (response.status === 404 || code === "model_not_found" || code === "model_decommissioned"
    || code === "model_permission_blocked" || reason === "model")
    return error(503, "PROVIDER_MODEL_UNAVAILABLE", "Groq could not access the configured model. Ask the project owner to check model availability and permissions");
  if (code === "context_length_exceeded" || response.status === 413)
    return error(502, "PROVIDER_CONTEXT_LIMIT", "Groq rejected the request size. Try a shorter task or goal description");
  if (code === "json_validate_failed" || code === "generation_failed" || reason === "generation")
    return error(502, "PROVIDER_GENERATION_FAILED", "Groq could not produce a breakdown matching the required format. Try again with clearer task details");
  if (code === "invalid_json_schema" || code === "json_schema_invalid" || reason === "schema"
    || diagnostic.parameter?.startsWith("response_format"))
    return error(502, "PROVIDER_SCHEMA_REJECTED", "Groq rejected the breakdown schema or structured-output settings. The server request needs attention");
  if (response.status === 400 || response.status === 422)
    return error(502, "PROVIDER_REQUEST_REJECTED", "Groq rejected the breakdown request. The server request settings need attention");
  return error(502, "PROVIDER_UNAVAILABLE", "Groq could not complete the request. Please try again later");
}

function connectionDiagnostic(error: unknown): string {
  // Never return exception.message/stack: a malformed header can expose the key.
  if (error instanceof TypeError) return "FETCH_TYPE_ERROR";
  if (error instanceof Error && error.name === "NetworkError") return "NETWORK_ERROR";
  return "FETCH_FAILED";
}

export async function generate(input: BreakdownInput, key: string): Promise<BreakdownOutput> {
  const apiKey = configuredGroqKey(key);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    let body: string;
    try { body = JSON.stringify(completionPayload(input)); }
    catch {
      throw new ApiError(503, "PROVIDER_REQUEST_CONFIGURATION", "The server could not prepare the AI request. Ask the project owner to check the backend.");
    }
    let response: Response;
    try {
      response = await fetch(GROQ_ENDPOINT, {
        // Workers rejects redirect: "error". Manual mode keeps credentials at Groq;
        // the non-OK response handler explicitly rejects any redirect response.
        method: "POST", redirect: "manual", signal: controller.signal,
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" }, body
      });
    } catch (error) {
      if (controller.signal.aborted) throw new ApiError(504, "AI_TIMEOUT", "The AI request timed out. Please try again.");
      throw new ApiError(502, "PROVIDER_CONNECTION",
        `The server could not reach Groq (${connectionDiagnostic(error)}). Please try again later.`);
    }
    if (!response.ok) throw rejected(response, await providerFailure(response, controller.signal));
    let raw: {
      choices?: { finish_reason?: string; message?: { content?: string; refusal?: unknown } }[];
    };
    try {
      raw = await readJsonLimited(response, 128 * 1024, REQUEST_TIMEOUT_MS, controller.signal) as typeof raw;
    } catch (error) {
      if (controller.signal.aborted || (error instanceof ApiError && error.status === 504))
        throw new ApiError(504, "AI_TIMEOUT", "The AI request timed out. Please try again.");
      if (error instanceof ApiError && error.code === "BODY_TOO_LARGE")
        throw new ApiError(502, "PROVIDER_RESPONSE_TOO_LARGE", "Groq returned an oversized response. Try a smaller task or goal.");
      throw new ApiError(502, "INVALID_AI_RESULT", "The AI provider returned an invalid response. Please try again.");
    }
    const choice = raw?.choices?.[0];
    if (choice?.finish_reason === "length")
      throw new ApiError(502, "AI_OUTPUT_LIMIT", "The breakdown exceeded the server's response allowance. Try a smaller task or goal.");
    if (choice?.message?.refusal || choice?.finish_reason === "content_filter")
      throw new ApiError(502, "AI_REFUSED", "The AI could not help with this request. Try rephrasing the task or goal.");
    if (!choice || choice.finish_reason !== "stop" || choice.message?.refusal || typeof choice.message?.content !== "string")
      throw new ApiError(502, "INCOMPLETE_AI_RESULT", "The AI could not finish a breakdown. Try adding clearer details and retry.");
    let content: unknown;
    try { content = JSON.parse(choice.message.content); }
    catch { throw new ApiError(502, "INVALID_AI_RESULT", "The AI returned an invalid breakdown. Please try again."); }
    return validateOutput(input.kind, content);
  } catch (error) {
    if (controller.signal.aborted) throw new ApiError(504, "AI_TIMEOUT", "The AI request timed out. Please try again.");
    if (error instanceof ApiError) throw error;
    // Unexpected processing errors are distinct from failures to connect.
    throw new ApiError(502, "PROVIDER_RESPONSE_PROCESSING", "The server could not process Groq's response. Ask the project owner to check the backend.");
  } finally { clearTimeout(timeout); }
}
