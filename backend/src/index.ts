import { authenticate } from "./auth";
import { ApiError, errorBody, jsonResponse, readJsonLimited } from "./http";
import { validateInput, UUID } from "./validation";
import type { Env } from "./types";
export { QuotaGate } from "./quota";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    let requestId: string = crypto.randomUUID();
    try {
      const url = new URL(request.url);
      const local = ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
      if (url.protocol !== "https:" && !local) throw new ApiError(400, "HTTPS_REQUIRED", "Use the HTTPS backend address.");
      if (url.pathname === "/health" && request.method === "GET")
        return jsonResponse({ service: "dailyplanner-ai", status: "ok" });
      if (url.pathname !== "/v1/breakdown") throw new ApiError(404, "NOT_FOUND", "This endpoint does not exist.");
      if (request.method !== "POST") {
        const response = jsonResponse(errorBody(new ApiError(405, "METHOD_NOT_ALLOWED", "Use POST for breakdown requests."), requestId), 405);
        response.headers.set("Allow", "POST");
        return response;
      }
      const userId = await authenticate(request, env);
      // Closed beta: public account creation does not grant use of the shared Groq key.
      const allowed = (env.ALLOWED_USER_IDS ?? "").split(",").map(id => id.trim()).filter(Boolean);
      if (allowed.some(id => !UUID.test(id))) throw new ApiError(503, "ACCESS_CONFIGURATION", "AI account access needs server configuration.");
      if (!allowed.includes(userId)) throw new ApiError(403, "ACCOUNT_NOT_ENABLED", "This account is not enabled for AI yet. Ask the project owner to enable it.");
      if (env.AI_ENABLED !== "true") throw new ApiError(503, "AI_DISABLED", "AI is not enabled on the server yet. Local planning is still available.");
      if ((request.headers.get("Content-Type") ?? "").split(";")[0]?.trim().toLowerCase() !== "application/json")
        throw new ApiError(415, "CONTENT_TYPE", "Send an application/json request.");
      const input = validateInput(await readJsonLimited(request, 16384, 2000, request.signal));
      requestId = input.requestId;
      const gate = env.QUOTA_GATE.get(env.QUOTA_GATE.idFromName("shared-usage-v1"));
      const result = await gate.run(userId, input);
      return jsonResponse(result.body, result.status);
    } catch (error) {
      // Never log request bodies, JWTs, Groq output, or exception/provider details.
      const safe = error instanceof ApiError ? error
        : new ApiError(503, "BACKEND_UNAVAILABLE", "The AI backend is temporarily unavailable. Please try again later.");
      return jsonResponse(errorBody(safe, requestId), safe.status);
    }
  }
} satisfies ExportedHandler<Env>;
