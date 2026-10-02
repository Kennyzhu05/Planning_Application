import type { ErrorBody, ProviderDiagnostic } from "./types";

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string,
    public retryAfterSeconds?: number, public provider?: ProviderDiagnostic) { super(message); }
}
export function errorBody(error: ApiError, requestId: string): ErrorBody {
  return { error: { code: error.code, message: error.message,
    ...(error.retryAfterSeconds ? { retryAfterSeconds: error.retryAfterSeconds } : {}),
    ...(error.provider ? { provider: error.provider } : {}) }, requestId };
}
export function jsonResponse(body: unknown, status = 200): Response {
  const retry = (body as ErrorBody)?.error?.retryAfterSeconds;
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...(retry ? { "Retry-After": String(retry) } : {})
    }
  });
}

// Bound streamed bodies as well as Content-Length. Timeout includes slow streaming.
export async function readJsonLimited(source: Request | Response, maxBytes: number,
  timeoutMs: number, signal?: AbortSignal): Promise<unknown> {
  const announced = Number(source.headers.get("content-length"));
  if (announced > maxBytes)
    throw new ApiError(413, "BODY_TOO_LARGE", "The request or response is too large.");
  if (!source.body) throw new ApiError(400, "INVALID_JSON", "An application/json body is required.");
  const reader = source.body.getReader();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let rejectInterrupted: (reason: Error) => void = () => {};
  const interrupted = new Promise<never>((_, reject) => { rejectInterrupted = reject; });
  const abort = () => rejectInterrupted(new ApiError(504, "TIMEOUT", "The request timed out. Please try again."));
  timer = setTimeout(abort, timeoutMs);
  signal?.addEventListener("abort", abort, { once: true });
  if (signal?.aborted) abort();
  try {
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const part = await Promise.race([reader.read(), interrupted]);
      if (part.done) break;
      size += part.value.byteLength;
      if (size > maxBytes) throw new ApiError(413, "BODY_TOO_LARGE", "The request or response is too large.");
      chunks.push(part.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    try { return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)); }
    catch { throw new ApiError(400, "INVALID_JSON", "The request must contain valid JSON."); }
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", abort);
    // Cancellation acknowledgement can stall on a failed upstream stream.
    // Do not let cleanup extend the request's timeout.
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}
