import { createRemoteJWKSet, jwtVerify } from "jose";
import { ApiError } from "./http";
import { UUID } from "./validation";
import type { Env } from "./types";

const keySets = new Map<string, ReturnType<typeof createRemoteJWKSet>>();
export function supabaseOrigin(env: Env): string {
  let url: URL;
  try { url = new URL(env.SUPABASE_URL); } catch { throw new ApiError(503, "NOT_CONFIGURED", "Account service is not configured."); }
  if (url.protocol !== "https:" || !/^[a-z0-9-]+\.supabase\.co$/.test(url.hostname)
    || url.port || url.username || url.password || url.search || url.hash || (url.pathname !== "/" && url.pathname !== ""))
    throw new ApiError(503, "NOT_CONFIGURED", "Account service is not configured.");
  return url.origin;
}
export async function authenticate(request: Request, env: Env): Promise<string> {
  const authorization = request.headers.get("Authorization") ?? "";
  if (authorization.length > 8192 || !/^Bearer [A-Za-z0-9._-]+$/.test(authorization))
    throw new ApiError(401, "SIGN_IN_REQUIRED", "Sign in to use AI breakdown.");
  const issuer = supabaseOrigin(env) + "/auth/v1";
  let jwks = keySets.get(issuer);
  if (!jwks) {
    jwks = createRemoteJWKSet(new URL(issuer + "/.well-known/jwks.json"), {
      timeoutDuration: 5000, cooldownDuration: 30000, cacheMaxAge: 600000
    });
    keySets.set(issuer, jwks);
  }
  try {
    const { payload } = await jwtVerify(authorization.slice(7), jwks, {
      issuer, audience: "authenticated", algorithms: ["ES256", "RS256"],
      requiredClaims: ["exp", "iat", "sub"], maxTokenAge: "24h", clockTolerance: 5
    });
    if (payload.role !== "authenticated" || payload.is_anonymous === true
      || typeof payload.sub !== "string" || !UUID.test(payload.sub)) throw new Error("Invalid identity");
    return payload.sub;
  } catch (error) {
    const code = error && typeof error === "object" && "code" in error ? error.code : undefined;
    if (code === "ERR_JWKS_TIMEOUT" || error instanceof TypeError)
      throw new ApiError(503, "AUTH_UNAVAILABLE", "The account service is temporarily unavailable. Try again later.");
    if (code === "ERR_JOSE_ALG_NOT_ALLOWED")
      throw new ApiError(401, "SESSION_SIGNING_UNSUPPORTED", "This session uses an unsupported signing key. The project owner must activate an ES256 or RS256 Supabase signing key, then sign in again.");
    if (code === "ERR_JWKS_INVALID" || code === "ERR_JWK_INVALID")
      throw new ApiError(503, "AUTH_CONFIGURATION", "The account service's public signing keys need attention. Ask the project owner to check Supabase JWT signing keys.");
    throw new ApiError(401, "SESSION_EXPIRED", "Your session expired or is invalid. Sign in again.");
  }
}
