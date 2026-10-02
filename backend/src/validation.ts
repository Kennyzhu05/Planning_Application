import { ApiError } from "./http";
import type { BreakdownInput, BreakdownOutput, Step } from "./types";

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function invalid(message: string): never { throw new ApiError(400, "INVALID_INPUT", message); }
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) invalid("Expected a JSON object.");
  return value as Record<string, unknown>;
}
function exactKeys(value: Record<string, unknown>, keys: string[]): void {
  if (Object.keys(value).some(key => !keys.includes(key)) || keys.some(key => !(key in value)))
    invalid("Required fields are missing or unsupported fields were supplied.");
}
function text(value: unknown, field: string, maximum: number, required = false): string {
  if (typeof value !== "string" || value.length > maximum || (required && !value.trim()))
    invalid(`${field} must be ${required ? "non-empty " : ""}text up to ${maximum} characters.`);
  return value.trim();
}
function date(value: unknown, field: string, optional = false): string {
  if (optional && value === "") return "";
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) invalid(`${field} must be a valid YYYY-MM-DD date.`);
  const parsed = new Date(value + "T00:00:00Z");
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value)
    invalid(`${field} must be a real calendar date.`);
  return value;
}
export function validateInput(value: unknown): BreakdownInput {
  const root = record(value);
  exactKeys(root, ["kind", "requestId", "context"]);
  if (typeof root.requestId !== "string" || !UUID.test(root.requestId)) invalid("requestId must be a UUID.");
  const context = record(root.context);
  const common = {
    title: text(context.title, "Title", 200, true),
    description: text(context.description, "Description", 4000),
    category: text(context.category, "Category", 80, true)
  };
  if (root.kind === "task") {
    exactKeys(context, ["title", "description", "category", "estimatedMinutes"]);
    if (typeof context.estimatedMinutes !== "number" || !Number.isInteger(context.estimatedMinutes)
      || context.estimatedMinutes < 1 || context.estimatedMinutes > 10080)
      invalid("The task estimate must be a whole number between 1 and 10080 minutes.");
    return { kind: "task", requestId: root.requestId, context: { ...common, estimatedMinutes: context.estimatedMinutes } };
  }
  if (root.kind === "goal") {
    exactKeys(context, ["title", "description", "category", "successCriteria", "startingPoint", "targetDate", "weeklyHours", "today"]);
    if (typeof context.weeklyHours !== "number" || !Number.isFinite(context.weeklyHours)
      || context.weeklyHours < 0 || context.weeklyHours > 168) invalid("Weekly availability must be between 0 and 168 hours.");
    return { kind: "goal", requestId: root.requestId, context: {
      ...common, successCriteria: text(context.successCriteria, "Success criteria", 2000),
      startingPoint: text(context.startingPoint, "Starting point", 2000),
      targetDate: date(context.targetDate, "Target date", true),
      today: date(context.today, "Today"), weeklyHours: context.weeklyHours
    } };
  }
  return invalid("kind must be task or goal.");
}
function steps(value: unknown): Step[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 12) invalid("Expected 1–12 steps.");
  return value.map(item => {
    const row = record(item);
    exactKeys(row, ["name", "description", "minutes"]);
    if (typeof row.minutes !== "number" || !Number.isInteger(row.minutes) || row.minutes < 1 || row.minutes > 120)
      invalid("Step durations must be whole minutes from 1 to 120.");
    return { name: text(row.name, "Step title", 200, true),
      description: text(row.description, "Step guidance", 1500, true), minutes: row.minutes };
  });
}
export function validateOutput(kind: BreakdownInput["kind"], value: unknown): BreakdownOutput {
  try {
    const root = record(value);
    if (kind === "task") {
      exactKeys(root, ["subtasks"]);
      return { subtasks: steps(root.subtasks) };
    }
    exactKeys(root, ["milestones", "tasks"]);
    if (!Array.isArray(root.milestones) || root.milestones.length < 1 || root.milestones.length > 8)
      invalid("Expected 1–8 milestones.");
    return { milestones: root.milestones.map(item => text(item, "Milestone", 200, true)), tasks: steps(root.tasks) };
  } catch {
    throw new ApiError(502, "INVALID_AI_RESULT", "The AI returned an invalid breakdown. Please try again.");
  }
}
