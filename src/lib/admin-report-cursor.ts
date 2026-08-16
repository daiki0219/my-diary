import { isUuid } from "@/lib/profile-data";
import {
  comparePostSearchRows,
  isPostSearchTimestamp,
} from "@/lib/search-cursor";
import { isReportStatus, type ReportStatus } from "@/lib/report";

const CURSOR_VERSION = 1;
const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;
const LOWERCASE_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

export type AdminReportCursor = {
  v: 1;
  status: ReportStatus;
  createdAt: string;
  reportId: string;
};

export type AdminReportOrder = {
  ascending: boolean;
  comparison: "gt" | "lt";
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function decodeOpaqueCursor(value: string): unknown | null {
  if (
    value.length === 0 ||
    value.length > CURSOR_MAX_LENGTH ||
    !CURSOR_CHARACTER_PATTERN.test(value)
  ) {
    return null;
  }

  try {
    const bytes = Buffer.from(value, "base64url");

    if (bytes.toString("base64url") !== value) {
      return null;
    }

    const json = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return JSON.parse(json) as unknown;
  } catch {
    return null;
  }
}

export function getAdminReportOrder(status: ReportStatus): AdminReportOrder {
  const ascending = status === "pending" || status === "reviewing";

  return { ascending, comparison: ascending ? "gt" : "lt" };
}

export function isAdminReportCursor(
  value: unknown,
  expectedStatus: ReportStatus,
): value is AdminReportCursor {
  return (
    typeof value === "object" &&
    value !== null &&
    hasExactKeys(value, ["v", "status", "createdAt", "reportId"]) &&
    "v" in value &&
    "status" in value &&
    "createdAt" in value &&
    "reportId" in value &&
    value.v === CURSOR_VERSION &&
    typeof value.status === "string" &&
    isReportStatus(value.status) &&
    value.status === expectedStatus &&
    typeof value.createdAt === "string" &&
    isPostSearchTimestamp(value.createdAt) &&
    typeof value.reportId === "string" &&
    LOWERCASE_UUID_PATTERN.test(value.reportId)
  );
}

export function encodeAdminReportCursor({
  status,
  createdAt,
  reportId,
}: Omit<AdminReportCursor, "v">) {
  const canonicalReportId = isUuid(reportId) ? reportId.toLowerCase() : null;

  if (
    !isReportStatus(status) ||
    !isPostSearchTimestamp(createdAt) ||
    !canonicalReportId
  ) {
    throw new Error("Cannot encode an invalid admin report cursor.");
  }

  return Buffer.from(
    JSON.stringify({
      v: CURSOR_VERSION,
      status,
      createdAt,
      reportId: canonicalReportId,
    }),
    "utf8",
  ).toString("base64url");
}

export function decodeAdminReportCursor(
  value: string,
  expectedStatus: ReportStatus,
): AdminReportCursor | null {
  const cursor = decodeOpaqueCursor(value);

  return isAdminReportCursor(cursor, expectedStatus) ? cursor : null;
}

export function compareAdminReportPositions(
  status: ReportStatus,
  left: { reportId: string; createdAt: string },
  right: { reportId: string; createdAt: string },
) {
  if (
    !isUuid(left.reportId) ||
    !isUuid(right.reportId) ||
    !isPostSearchTimestamp(left.createdAt) ||
    !isPostSearchTimestamp(right.createdAt)
  ) {
    throw new Error("Cannot compare an invalid admin report position.");
  }

  const descendingComparison = comparePostSearchRows(
    { id: left.reportId.toLowerCase(), created_at: left.createdAt },
    { id: right.reportId.toLowerCase(), created_at: right.createdAt },
  );

  return getAdminReportOrder(status).ascending
    ? -descendingComparison
    : descendingComparison;
}
