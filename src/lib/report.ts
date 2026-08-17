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

export const REPORT_TARGET_TYPE_LABELS = {
  exchange_entry: "交換日記",
  user: "ユーザー",
} as const satisfies Record<ReportTargetType, string>;

export const REPORT_REASON_LABELS = {
  harassment: "嫌がらせ・誹謗中傷",
  spam: "スパム・大量投稿",
  personal_information: "個人情報",
  sexual_or_inappropriate: "性的・不適切な内容",
  threat_or_danger: "脅迫・危険な内容",
  other: "その他",
} as const satisfies Record<ReportReason, string>;

export const REPORT_STATUS_LABELS = {
  pending: "未対応",
  reviewing: "確認中",
  resolved: "対応済み",
  dismissed: "却下",
} as const satisfies Record<ReportStatus, string>;

export function isReportTargetType(value: unknown): value is ReportTargetType {
  return REPORT_TARGET_TYPES.some((targetType) => targetType === value);
}

export function isReportReason(value: unknown): value is ReportReason {
  return REPORT_REASONS.some((reason) => reason === value);
}

export function isReportStatus(value: unknown): value is ReportStatus {
  return REPORT_STATUSES.some((status) => status === value);
}
