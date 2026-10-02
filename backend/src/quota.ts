import { DurableObject } from "cloudflare:workers";
import { ApiError, errorBody } from "./http";
import { generate, configuredGroqKey } from "./groq";
import type { Env, BreakdownInput, GateResult } from "./types";

// Every user reaches the SAME named object. Reservation and counters are atomic
// across Workers and regions; eventually-consistent rate-limit bindings are not billing guards.
export class QuotaGate extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS counters (
      scope TEXT NOT NULL, bucket TEXT NOT NULL, count INTEGER NOT NULL,
      expires_at INTEGER NOT NULL, PRIMARY KEY (scope, bucket))`);
    ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS requests (
      user_id TEXT NOT NULL, request_id TEXT NOT NULL, lease_until INTEGER NOT NULL,
      expires_at INTEGER NOT NULL, PRIMARY KEY (user_id, request_id))`);
  }
  private limit(value: string): number {
    if (!/^[1-9][0-9]*$/.test(value)) throw new ApiError(503, "LIMITS_CONFIGURATION", "AI usage limits need server configuration.");
    const result = Number(value);
    if (!Number.isSafeInteger(result) || result > 1000000) throw new ApiError(503, "LIMITS_CONFIGURATION", "AI usage limits need server configuration.");
    return result;
  }
  async run(userId: string, input: BreakdownInput): Promise<GateResult> {
    const now = Date.now();
    try {
      if (this.env.AI_ENABLED !== "true")
        throw new ApiError(503, "AI_DISABLED", "AI is not enabled on the server yet. Local planning is still available.");
      // Missing/malformed credentials fail before consuming a usage reservation.
      const key = configuredGroqKey(this.env.GROQ_API_KEY);
      const date = new Date(now);
      const day = date.toISOString().slice(0, 10), month = day.slice(0, 7);
      const nextDay = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + 1);
      const nextMonth = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1);
      const minuteEnd = (Math.floor(now / 60000) + 1) * 60000;
      const budgets = [
        { scope: `user-minute:${userId}`, bucket: String(Math.floor(now / 60000)), end: minuteEnd,
          limit: this.limit(this.env.USER_REQUESTS_PER_MINUTE), global: false },
        { scope: `user-day:${userId}`, bucket: day, end: nextDay,
          limit: this.limit(this.env.USER_REQUESTS_PER_DAY), global: false },
        { scope: "global-day", bucket: day, end: nextDay,
          limit: this.limit(this.env.GLOBAL_REQUESTS_PER_DAY), global: true },
        { scope: "global-month", bucket: month, end: nextMonth,
          limit: this.limit(this.env.GLOBAL_REQUESTS_PER_MONTH), global: true }
      ];
      const concurrency = this.limit(this.env.GLOBAL_CONCURRENT_REQUESTS);
      this.ctx.storage.transactionSync(() => {
        const sql = this.ctx.storage.sql;
        sql.exec("DELETE FROM counters WHERE expires_at <= ?", now);
        sql.exec("DELETE FROM requests WHERE expires_at <= ?", now);
        if (sql.exec("SELECT 1 FROM requests WHERE user_id = ? AND request_id = ?", userId, input.requestId).toArray().length)
          throw new ApiError(409, "DUPLICATE_REQUEST", "This request was already submitted. Use the breakdown button again for a new attempt.");
        if (sql.exec("SELECT 1 FROM requests WHERE user_id = ? AND lease_until > ?", userId, now).toArray().length)
          throw new ApiError(429, "USER_BUSY", "Your account already has an AI request running. Wait a moment and retry.", 45);
        const active = sql.exec<{ count: number }>("SELECT COUNT(*) AS count FROM requests WHERE lease_until > ?", now).one().count;
        if (active >= concurrency) throw new ApiError(429, "SERVER_BUSY", "AI is busy with another request. Please try again shortly.", 30);
        for (const budget of budgets) {
          const count = sql.exec<{ count: number }>("SELECT count FROM counters WHERE scope = ? AND bucket = ?", budget.scope, budget.bucket).toArray()[0]?.count ?? 0;
          if (count >= budget.limit) throw new ApiError(429, budget.global ? "GLOBAL_USAGE_CAP" : "USER_USAGE_LIMIT",
            budget.global ? "The shared AI usage allowance is used up. Try again after it resets."
              : "Your AI usage allowance for this period is used up. Try again after it resets.",
            Math.max(1, Math.ceil((budget.end - now) / 1000)));
        }
        for (const budget of budgets) sql.exec(`INSERT INTO counters (scope, bucket, count, expires_at) VALUES (?, ?, 1, ?)
          ON CONFLICT(scope, bucket) DO UPDATE SET count = count + 1`, budget.scope, budget.bucket, budget.end);
        sql.exec("INSERT INTO requests (user_id, request_id, lease_until, expires_at) VALUES (?, ?, ?, ?)",
          userId, input.requestId, now + 60000, now + 86400000);
      });
      // A reservation remains counted on ALL outcomes, including timeout/cancellation.
      // Releasing only the concurrency lease cannot refund unknown provider usage.
      try {
        const output = await generate(input, key);
        const body = { ...output, requestId: input.requestId, kind: input.kind };
        if (new TextEncoder().encode(JSON.stringify(body)).byteLength > 65536)
          throw new ApiError(502, "INVALID_AI_RESULT", "The AI returned an oversized breakdown. Please try again.");
        return { status: 200, body };
      } finally {
        try {
          this.ctx.storage.sql.exec("UPDATE requests SET lease_until = 0 WHERE user_id = ? AND request_id = ?", userId, input.requestId);
        } catch {
          // Preserve the result/provider error if cleanup fails. The existing
          // lease expires after 60 seconds; usage counters are never refunded.
        }
      }
    } catch (error) {
      const safe = error instanceof ApiError ? error
        : new ApiError(503, "AI_UNAVAILABLE", "AI is temporarily unavailable. Please try again later.");
      return { status: safe.status, body: errorBody(safe, input.requestId) };
    }
  }
}
