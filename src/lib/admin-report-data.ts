import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import {
  compareAdminReportPositions,
  encodeAdminReportCursor,
  getAdminReportOrder,
  isAdminReportCursor,
  type AdminReportCursor,
} from "@/lib/admin-report-cursor";
import { isUuid } from "@/lib/profile-data";
import {
  isReportReason,
  isReportStatus,
  isReportTargetType,
  type ReportReason,
  type ReportStatus,
  type ReportTargetType,
} from "@/lib/report";
import { isPostSearchTimestamp } from "@/lib/search-cursor";
import {
  getAdminSessionState,
  type AdminSessionState,
} from "@/lib/supabase/admin-session";
import { createClient } from "@/lib/supabase/server";

export const ADMIN_REPORT_PAGE_SIZE = 20;

const ADMIN_REPORT_LIST_SELECT = [
  "id",
  "target_type",
  "reason",
  "status",
  "created_at",
].join(", ");

export type AdminReportListItem = {
  reportId: string;
  targetType: ReportTargetType;
  reason: ReportReason;
  status: ReportStatus;
  createdAt: string;
};

export type AdminReportPageResult =
  | {
      kind: "success";
      items: AdminReportListItem[];
      nextCursor: string | null;
    }
  | Exclude<AdminSessionState, { kind: "active-admin" }>
  | { kind: "invalid-query" }
  | { kind: "error" };

export type AdminReportPageInput = {
  status: ReportStatus;
  cursor: AdminReportCursor | null;
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

export function parseAdminReportListItem(
  value: unknown,
): AdminReportListItem | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, [
      "id",
      "target_type",
      "reason",
      "status",
      "created_at",
    ]) ||
    !("id" in value) ||
    !("target_type" in value) ||
    !("reason" in value) ||
    !("status" in value) ||
    !("created_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    !isReportTargetType(value.target_type) ||
    !isReportReason(value.reason) ||
    !isReportStatus(value.status) ||
    typeof value.created_at !== "string" ||
    !isPostSearchTimestamp(value.created_at)
  ) {
    return null;
  }

  return {
    reportId: value.id.toLowerCase(),
    targetType: value.target_type,
    reason: value.reason,
    status: value.status,
    createdAt: value.created_at,
  };
}

async function loadAdminReportPage(
  supabase: SupabaseClient,
  input: AdminReportPageInput,
): Promise<Extract<AdminReportPageResult, { kind: "success" | "error" }>> {
  const { status, cursor } = input;

  if (
    !isReportStatus(status) ||
    (cursor !== null && !isAdminReportCursor(cursor, status))
  ) {
    return { kind: "error" };
  }

  const order = getAdminReportOrder(status);
  let query = supabase
    .from("reports")
    .select(ADMIN_REPORT_LIST_SELECT)
    .eq("status", status)
    .order("created_at", { ascending: order.ascending })
    .order("id", { ascending: order.ascending })
    .limit(ADMIN_REPORT_PAGE_SIZE + 1);

  if (cursor) {
    query = query.or(
      `created_at.${order.comparison}.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.${order.comparison}.${cursor.reportId})`,
    );
  }

  let result;

  try {
    result = await query.returns<unknown[]>();
  } catch {
    return { kind: "error" };
  }

  if (
    result.error ||
    !Array.isArray(result.data) ||
    result.data.length > ADMIN_REPORT_PAGE_SIZE + 1
  ) {
    return { kind: "error" };
  }

  const parsedItems: AdminReportListItem[] = [];
  const reportIds = new Set<string>();

  for (const value of result.data) {
    const item = parseAdminReportListItem(value);

    if (
      !item ||
      item.status !== status ||
      reportIds.has(item.reportId) ||
      (parsedItems.length > 0 &&
        compareAdminReportPositions(
          status,
          parsedItems[parsedItems.length - 1],
          item,
        ) >= 0)
    ) {
      return { kind: "error" };
    }

    reportIds.add(item.reportId);
    parsedItems.push(item);
  }

  const items = parsedItems.slice(0, ADMIN_REPORT_PAGE_SIZE);
  const cursorItem = items.at(-1);
  const nextCursor =
    parsedItems.length > ADMIN_REPORT_PAGE_SIZE && cursorItem
      ? encodeAdminReportCursor({
          status,
          createdAt: cursorItem.createdAt,
          reportId: cursorItem.reportId,
        })
      : null;

  return { kind: "success", items, nextCursor };
}

export async function getAdminReportPage(
  input: AdminReportPageInput | null,
): Promise<AdminReportPageResult> {
  let supabase;

  try {
    supabase = await createClient();
  } catch {
    return { kind: "query-error" };
  }

  const adminSession = await getAdminSessionState(supabase);

  if (adminSession.kind !== "active-admin") {
    return adminSession;
  }

  if (input === null) {
    return { kind: "invalid-query" };
  }

  return loadAdminReportPage(supabase, input);
}
