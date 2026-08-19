import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { isPostMood, type PostMood } from "@/lib/post-data";
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
import {
  compareCanonicalTagNames,
  normalizeTagName,
} from "@/lib/tag-data";

const REPORT_DETAIL_SELECT = [
  "target_type",
  "reason",
  "details",
  "status",
  "created_at",
  "resolved_at",
].join(", ");

const REPORT_SNAPSHOT_SELECT = [
  "entry_created_at",
  "entry_updated_at",
  "captured_at",
  "title",
  "body",
  "mood",
  "location_name",
  "tag_names",
].join(", ");

const REPORT_EVIDENCE_SELECT = [
  "id",
  "sort_order",
  "mime_type",
  "size_bytes",
].join(", ");

const REPORT_EVIDENCE_MAX_ITEMS = 10;
const REPORT_EVIDENCE_MAX_SIZE_BYTES = 6 * 1024 * 1024;
const TAG_CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f-\u009f]/u;

export type AdminReportEvidenceItem = {
  evidenceId: string;
  sortOrder: number;
  mimeType: "image/jpeg" | "image/png" | "image/webp";
  sizeBytes: number;
};

export type AdminReportDetail = {
  report: {
    targetType: ReportTargetType;
    reason: ReportReason;
    details: string | null;
    status: ReportStatus;
    createdAt: string;
    resolvedAt: string | null;
  };
  snapshot: {
    entryCreatedAt: string;
    entryUpdatedAt: string;
    capturedAt: string;
    title: string | null;
    body: string;
    mood: PostMood | null;
    locationName: string | null;
    tagNames: string[];
  } | null;
  evidence: AdminReportEvidenceItem[];
};

export type AdminReportDetailResult =
  | { kind: "success"; detail: AdminReportDetail }
  | Exclude<AdminSessionState, { kind: "active-admin" }>
  | { kind: "not-found" }
  | { kind: "error" };

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function isBoundedTrimmedString(
  value: unknown,
  maxCodePoints: number,
): value is string {
  return (
    typeof value === "string" &&
    Array.from(value).length >= 1 &&
    Array.from(value).length <= maxCodePoints &&
    value.trim() === value
  );
}

function isNullableBoundedTrimmedString(
  value: unknown,
  maxCodePoints: number,
): value is string | null {
  return value === null || isBoundedTrimmedString(value, maxCodePoints);
}

function isCanonicalTagNames(value: unknown): value is string[] {
  if (!Array.isArray(value) || value.length > 5) {
    return false;
  }

  for (let index = 0; index < value.length; index += 1) {
    const tag = value[index];

    if (
      !isBoundedTrimmedString(tag, 30) ||
      normalizeTagName(tag) !== tag ||
      tag.includes(",") ||
      tag.includes("#") ||
      TAG_CONTROL_CHARACTER_PATTERN.test(tag) ||
      (index > 0 &&
        compareCanonicalTagNames(value[index - 1], tag) >= 0)
    ) {
      return false;
    }
  }

  return true;
}

function parseReportRow(value: unknown): AdminReportDetail["report"] | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, [
      "target_type",
      "reason",
      "details",
      "status",
      "created_at",
      "resolved_at",
    ]) ||
    !("target_type" in value) ||
    !("reason" in value) ||
    !("details" in value) ||
    !("status" in value) ||
    !("created_at" in value) ||
    !("resolved_at" in value) ||
    !isReportTargetType(value.target_type) ||
    !isReportReason(value.reason) ||
    !isNullableBoundedTrimmedString(value.details, 2_000) ||
    !isReportStatus(value.status) ||
    typeof value.created_at !== "string" ||
    !isPostSearchTimestamp(value.created_at) ||
    (value.resolved_at !== null &&
      (typeof value.resolved_at !== "string" ||
        !isPostSearchTimestamp(value.resolved_at))) ||
    (value.reason === "other" && value.details === null) ||
    ((value.status === "pending" || value.status === "reviewing") &&
      value.resolved_at !== null) ||
    ((value.status === "resolved" || value.status === "dismissed") &&
      value.resolved_at === null)
  ) {
    return null;
  }

  return {
    targetType: value.target_type,
    reason: value.reason,
    details: value.details,
    status: value.status,
    createdAt: value.created_at,
    resolvedAt: value.resolved_at,
  };
}

function parseSnapshotRow(
  value: unknown,
): NonNullable<AdminReportDetail["snapshot"]> | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, [
      "entry_created_at",
      "entry_updated_at",
      "captured_at",
      "title",
      "body",
      "mood",
      "location_name",
      "tag_names",
    ]) ||
    !("entry_created_at" in value) ||
    !("entry_updated_at" in value) ||
    !("captured_at" in value) ||
    !("title" in value) ||
    !("body" in value) ||
    !("mood" in value) ||
    !("location_name" in value) ||
    !("tag_names" in value) ||
    typeof value.entry_created_at !== "string" ||
    !isPostSearchTimestamp(value.entry_created_at) ||
    typeof value.entry_updated_at !== "string" ||
    !isPostSearchTimestamp(value.entry_updated_at) ||
    typeof value.captured_at !== "string" ||
    !isPostSearchTimestamp(value.captured_at) ||
    !isNullableBoundedTrimmedString(value.title, 120) ||
    !isBoundedTrimmedString(value.body, 10_000) ||
    (value.mood !== null &&
      (typeof value.mood !== "string" || !isPostMood(value.mood))) ||
    !isNullableBoundedTrimmedString(value.location_name, 100) ||
    !isCanonicalTagNames(value.tag_names)
  ) {
    return null;
  }

  return {
    entryCreatedAt: value.entry_created_at,
    entryUpdatedAt: value.entry_updated_at,
    capturedAt: value.captured_at,
    title: value.title,
    body: value.body,
    mood: value.mood,
    locationName: value.location_name,
    tagNames: [...value.tag_names],
  };
}

function parseEvidenceRow(
  value: unknown,
): AdminReportDetail["evidence"][number] | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, ["id", "sort_order", "mime_type", "size_bytes"]) ||
    !("id" in value) ||
    !("sort_order" in value) ||
    !("mime_type" in value) ||
    !("size_bytes" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.sort_order !== "number" ||
    !Number.isInteger(value.sort_order) ||
    value.sort_order < 0 ||
    value.sort_order > 9 ||
    (value.mime_type !== "image/jpeg" &&
      value.mime_type !== "image/png" &&
      value.mime_type !== "image/webp") ||
    typeof value.size_bytes !== "number" ||
    !Number.isSafeInteger(value.size_bytes) ||
    value.size_bytes < 1 ||
    value.size_bytes > REPORT_EVIDENCE_MAX_SIZE_BYTES
  ) {
    return null;
  }

  return {
    evidenceId: value.id.toLowerCase(),
    sortOrder: value.sort_order,
    mimeType: value.mime_type,
    sizeBytes: value.size_bytes,
  };
}

async function loadVisibleReport(
  supabase: SupabaseClient,
  reportId: string,
): Promise<
  | { kind: "success"; report: AdminReportDetail["report"] }
  | { kind: "not-found" | "error" }
> {
  let result;

  try {
    result = await supabase
      .from("reports")
      .select(REPORT_DETAIL_SELECT)
      .eq("id", reportId)
      .limit(2)
      .returns<unknown[]>();
  } catch {
    return { kind: "error" };
  }

  if (result.error || !Array.isArray(result.data) || result.data.length > 1) {
    return { kind: "error" };
  }

  if (result.data.length === 0) {
    return { kind: "not-found" };
  }

  const report = parseReportRow(result.data[0]);

  return report ? { kind: "success", report } : { kind: "error" };
}

async function loadReportSnapshotAndEvidence(
  supabase: SupabaseClient,
  reportId: string,
): Promise<
  | Pick<AdminReportDetail, "snapshot" | "evidence">
  | { kind: "error" }
> {
  let snapshotResult;
  let evidenceResult;

  try {
    [snapshotResult, evidenceResult] = await Promise.all([
      supabase
        .from("report_exchange_entry_snapshots")
        .select(REPORT_SNAPSHOT_SELECT)
        .eq("report_id", reportId)
        .limit(2)
        .returns<unknown[]>(),
      supabase
        .from("report_snapshot_images")
        .select(REPORT_EVIDENCE_SELECT)
        .eq("report_id", reportId)
        .order("sort_order", { ascending: true })
        .limit(REPORT_EVIDENCE_MAX_ITEMS + 1)
        .returns<unknown[]>(),
    ]);
  } catch {
    return { kind: "error" };
  }

  if (
    snapshotResult.error ||
    evidenceResult.error ||
    !Array.isArray(snapshotResult.data) ||
    !Array.isArray(evidenceResult.data) ||
    snapshotResult.data.length > 1 ||
    evidenceResult.data.length > REPORT_EVIDENCE_MAX_ITEMS
  ) {
    return { kind: "error" };
  }

  const snapshot =
    snapshotResult.data.length === 0
      ? null
      : parseSnapshotRow(snapshotResult.data[0]);

  if (snapshotResult.data.length === 1 && !snapshot) {
    return { kind: "error" };
  }

  const evidence: AdminReportDetail["evidence"] = [];
  const evidenceIds = new Set<string>();

  for (const value of evidenceResult.data) {
    const item = parseEvidenceRow(value);

    if (
      !item ||
      evidenceIds.has(item.evidenceId) ||
      (evidence.length > 0 &&
        evidence[evidence.length - 1].sortOrder >= item.sortOrder)
    ) {
      return { kind: "error" };
    }

    evidenceIds.add(item.evidenceId);
    evidence.push(item);
  }

  if (snapshot === null && evidence.length > 0) {
    return { kind: "error" };
  }

  return { snapshot, evidence };
}

export async function getAdminReportDetail(
  rawReportId: string,
): Promise<AdminReportDetailResult> {
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

  if (!isUuid(rawReportId)) {
    return { kind: "not-found" };
  }

  const reportId = rawReportId.toLowerCase();
  const reportResult = await loadVisibleReport(supabase, reportId);

  if (reportResult.kind !== "success") {
    return reportResult;
  }

  const relatedResult = await loadReportSnapshotAndEvidence(
    supabase,
    reportId,
  );

  if ("kind" in relatedResult) {
    return relatedResult;
  }

  return {
    kind: "success",
    detail: {
      report: reportResult.report,
      snapshot: relatedResult.snapshot,
      evidence: relatedResult.evidence,
    },
  };
}
