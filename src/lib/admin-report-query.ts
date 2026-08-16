import {
  decodeAdminReportCursor,
  type AdminReportCursor,
} from "@/lib/admin-report-cursor";
import { isReportStatus, type ReportStatus } from "@/lib/report";

export type AdminReportSearchParams = Record<
  string,
  string | string[] | undefined
>;

export type AdminReportQuery = {
  status: ReportStatus;
  cursor: AdminReportCursor | null;
};

function hasOnlyKeys(
  searchParams: AdminReportSearchParams,
  allowedKeys: readonly string[],
) {
  return Object.keys(searchParams).every((key) => allowedKeys.includes(key));
}

function readOptionalSingleValue(value: string | string[] | undefined) {
  if (value === undefined) {
    return { valid: true, value: null } as const;
  }

  if (typeof value !== "string" || value.length === 0) {
    return { valid: false, value: null } as const;
  }

  return { valid: true, value } as const;
}

export function parseAdminReportQuery(
  searchParams: AdminReportSearchParams,
): AdminReportQuery | null {
  if (!hasOnlyKeys(searchParams, ["status", "cursor"])) {
    return null;
  }

  const rawStatus = readOptionalSingleValue(searchParams.status);
  const rawCursor = readOptionalSingleValue(searchParams.cursor);

  if (!rawStatus.valid || !rawCursor.valid) {
    return null;
  }

  const status = rawStatus.value ?? "pending";

  if (!isReportStatus(status)) {
    return null;
  }

  const cursor = rawCursor.value
    ? decodeAdminReportCursor(rawCursor.value, status)
    : null;

  if (rawCursor.value && !cursor) {
    return null;
  }

  return { status, cursor };
}
