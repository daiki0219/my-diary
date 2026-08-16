export const REPORT_TARGET_TYPES = ["exchange_entry", "user"] as const;

export const REPORT_REASONS = [
  "harassment",
  "spam",
  "personal_information",
  "sexual_or_inappropriate",
  "threat_or_danger",
  "other",
] as const;

export const REPORT_STATUSES = [
  "pending",
  "reviewing",
  "resolved",
  "dismissed",
] as const;

export type ReportTargetType = (typeof REPORT_TARGET_TYPES)[number];
export type ReportReason = (typeof REPORT_REASONS)[number];
export type ReportStatus = (typeof REPORT_STATUSES)[number];

export function isReportTargetType(value: unknown): value is ReportTargetType {
  return REPORT_TARGET_TYPES.some((targetType) => targetType === value);
}

export function isReportReason(value: unknown): value is ReportReason {
  return REPORT_REASONS.some((reason) => reason === value);
}

export function isReportStatus(value: unknown): value is ReportStatus {
  return REPORT_STATUSES.some((status) => status === value);
}
