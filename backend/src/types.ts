import type { QuotaGate } from "./quota";

export interface Env {
  GROQ_API_KEY?: string;
  SUPABASE_URL: string;
  ALLOWED_USER_IDS: string;
  AI_ENABLED: string;
  USER_REQUESTS_PER_MINUTE: string;
  USER_REQUESTS_PER_DAY: string;
  GLOBAL_REQUESTS_PER_DAY: string;
  GLOBAL_REQUESTS_PER_MONTH: string;
  GLOBAL_CONCURRENT_REQUESTS: string;
  QUOTA_GATE: DurableObjectNamespace<QuotaGate>;
}

interface CommonContext { title: string; description: string; category: string }
export type BreakdownInput =
  | { kind: "task"; requestId: string; context: CommonContext & { estimatedMinutes: number } }
  | { kind: "goal"; requestId: string; context: CommonContext & {
      successCriteria: string; startingPoint: string; targetDate: string;
      weeklyHours: number; today: string;
    } };
export interface Step { name: string; description: string; minutes: number }
export type BreakdownOutput = { subtasks: Step[] } | { milestones: string[]; tasks: Step[] };
export interface ProviderDiagnostic {
  status: number;
  code?: string;
  parameter?: string;
}
export interface ErrorBody {
  error: { code: string; message: string; retryAfterSeconds?: number; provider?: ProviderDiagnostic };
  requestId: string;
}
export interface GateResult { status: number; body: ErrorBody | (BreakdownOutput & { requestId: string; kind: string }) }
