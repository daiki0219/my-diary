import type { ReportStatus } from "@/lib/report";

export type AdminReportNextStatus = Extract<
  ReportStatus,
  "reviewing" | "resolved" | "dismissed"
>;

const ADMIN_REPORT_STATUS_TRANSITIONS = {
  pending: ["reviewing", "resolved", "dismissed"],
  reviewing: ["resolved", "dismissed"],
  resolved: [],
  dismissed: [],
} as const satisfies Record<
  ReportStatus,
  readonly AdminReportNextStatus[]
>;

export function isAdminReportNextStatus(
  value: unknown,
): value is AdminReportNextStatus {
  return (
    value === "reviewing" || value === "resolved" || value === "dismissed"
  );
}

export function canTransitionAdminReportStatus(
  currentStatus: ReportStatus,
  nextStatus: AdminReportNextStatus,
) {
  if (currentStatus === "pending") {
    return (
      nextStatus === "reviewing" ||
      nextStatus === "resolved" ||
      nextStatus === "dismissed"
    );
  }

  return (
    currentStatus === "reviewing" &&
    (nextStatus === "resolved" || nextStatus === "dismissed")
  );
}

export function getAdminReportStatusTransitions(
  currentStatus: ReportStatus,
): readonly AdminReportNextStatus[] {
  return ADMIN_REPORT_STATUS_TRANSITIONS[currentStatus];
}
