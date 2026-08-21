import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { isUuid } from "@/lib/profile-data";
import { isReportStatus } from "@/lib/report";
import { isPostSearchTimestamp } from "@/lib/search-cursor";
import {
  getAdminSessionState,
  type AdminSessionState,
} from "@/lib/supabase/admin-session";
import { createClient } from "@/lib/supabase/server";
import { parseExchangeEntryImageStoragePath } from "@/lib/exchange-entry-image-input";

export const ADMIN_EVIDENCE_PURGE_BATCH_SIZE = 10;
export const ADMIN_EXCHANGE_IMAGE_CLEANUP_BATCH_SIZE = 10;

const SUMMARY_KEYS = [
  "due_confirmed_cleanup_candidate_count",
  "oldest_confirmed_cleanup_due_at",
  "due_unconfirmed_orphan_count",
  "oldest_unconfirmed_orphan_due_at",
  "due_report_evidence_count",
  "oldest_report_evidence_due_at",
] as const;

const SNAPSHOT_CANDIDATE_SELECT = [
  "id",
  "status",
  "evidence_delete_after",
  "snapshot:report_exchange_entry_snapshots!inner(report_id)",
].join(", ");

const IMAGE_CANDIDATE_SELECT = [
  "id",
  "status",
  "evidence_delete_after",
  "snapshot_images:report_snapshot_images!inner(report_id)",
].join(", ");

export type AdminMaintenanceSummary = {
  dueConfirmedCleanupCandidateCount: number;
  oldestConfirmedCleanupDueAt: string | null;
  dueUnconfirmedOrphanCount: number;
  oldestUnconfirmedOrphanDueAt: string | null;
  dueReportEvidenceCount: number;
  oldestReportEvidenceDueAt: string | null;
};

export type AdminMaintenanceSummaryResult =
  | { kind: "success"; summary: AdminMaintenanceSummary }
  | Exclude<AdminSessionState, { kind: "active-admin" }>
  | { kind: "error" };

export type DueReportEvidenceCandidate = {
  reportId: string;
  evidenceDeleteAfter: string;
};

export type DueReportEvidenceCandidateResult =
  | { kind: "success"; candidates: DueReportEvidenceCandidate[] }
  | { kind: "error" };

export type DueExchangeImageCleanupCandidateResult =
  | { kind: "success"; storagePaths: string[] }
  | { kind: "unavailable" | "failed" | "unknown" };

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function isCount(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isSafeInteger(value) &&
    value >= 0
  );
}

function isOldestDueAt(value: unknown, count: number): value is string | null {
  return count === 0
    ? value === null
    : typeof value === "string" && isPostSearchTimestamp(value);
}

function parseSummaryRow(value: unknown): AdminMaintenanceSummary | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, SUMMARY_KEYS) ||
    !("due_confirmed_cleanup_candidate_count" in value) ||
    !("oldest_confirmed_cleanup_due_at" in value) ||
    !("due_unconfirmed_orphan_count" in value) ||
    !("oldest_unconfirmed_orphan_due_at" in value) ||
    !("due_report_evidence_count" in value) ||
    !("oldest_report_evidence_due_at" in value) ||
    !isCount(value.due_confirmed_cleanup_candidate_count) ||
    !isOldestDueAt(
      value.oldest_confirmed_cleanup_due_at,
      value.due_confirmed_cleanup_candidate_count,
    ) ||
    !isCount(value.due_unconfirmed_orphan_count) ||
    !isOldestDueAt(
      value.oldest_unconfirmed_orphan_due_at,
      value.due_unconfirmed_orphan_count,
    ) ||
    !isCount(value.due_report_evidence_count) ||
    !isOldestDueAt(
      value.oldest_report_evidence_due_at,
      value.due_report_evidence_count,
    )
  ) {
    return null;
  }

  return {
    dueConfirmedCleanupCandidateCount:
      value.due_confirmed_cleanup_candidate_count,
    oldestConfirmedCleanupDueAt: value.oldest_confirmed_cleanup_due_at,
    dueUnconfirmedOrphanCount: value.due_unconfirmed_orphan_count,
    oldestUnconfirmedOrphanDueAt: value.oldest_unconfirmed_orphan_due_at,
    dueReportEvidenceCount: value.due_report_evidence_count,
    oldestReportEvidenceDueAt: value.oldest_report_evidence_due_at,
  };
}

export async function loadAdminMaintenanceSummary(
  supabase: SupabaseClient,
): Promise<
  | { kind: "success"; summary: AdminMaintenanceSummary }
  | { kind: "error" }
> {
  let result;

  try {
    result = await supabase.rpc("my_diary_get_maintenance_backlog_summary");
  } catch {
    return { kind: "error" };
  }

  if (
    result.error ||
    !Array.isArray(result.data) ||
    result.data.length !== 1
  ) {
    return { kind: "error" };
  }

  const summary = parseSummaryRow(result.data[0]);

  return summary ? { kind: "success", summary } : { kind: "error" };
}

export async function getAdminMaintenanceSummary(): Promise<AdminMaintenanceSummaryResult> {
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

  return loadAdminMaintenanceSummary(supabase);
}

function parseDueExchangeImageStoragePaths(value: unknown): string[] | null {
  if (
    !Array.isArray(value) ||
    value.length > ADMIN_EXCHANGE_IMAGE_CLEANUP_BATCH_SIZE
  ) {
    return null;
  }

  const storagePaths: string[] = [];
  const seenStoragePaths = new Set<string>();

  for (const storagePath of value) {
    if (
      typeof storagePath !== "string" ||
      !parseExchangeEntryImageStoragePath(storagePath) ||
      seenStoragePaths.has(storagePath)
    ) {
      return null;
    }

    seenStoragePaths.add(storagePath);
    storagePaths.push(storagePath);
  }

  return storagePaths;
}

async function listDueExchangeImageStoragePaths(
  supabase: SupabaseClient,
  rpcName:
    | "my_diary_list_due_exchange_image_cleanup_candidates"
    | "my_diary_list_due_unconfirmed_exchange_image_orphans",
): Promise<DueExchangeImageCleanupCandidateResult> {
  let result;

  try {
    result = await supabase.rpc(rpcName, {
      p_limit: ADMIN_EXCHANGE_IMAGE_CLEANUP_BATCH_SIZE,
    });
  } catch {
    return { kind: "unknown" };
  }

  if (result.error) {
    if (result.status === 0) {
      return { kind: "unknown" };
    }

    return {
      kind: result.error.code === "42501" ? "unavailable" : "failed",
    };
  }

  const storagePaths = parseDueExchangeImageStoragePaths(result.data);

  return storagePaths
    ? { kind: "success", storagePaths }
    : { kind: "unknown" };
}

export function listDueConfirmedExchangeImageCleanupCandidates(
  supabase: SupabaseClient,
) {
  return listDueExchangeImageStoragePaths(
    supabase,
    "my_diary_list_due_exchange_image_cleanup_candidates",
  );
}

export function listDueUnconfirmedExchangeImageOrphans(
  supabase: SupabaseClient,
) {
  return listDueExchangeImageStoragePaths(
    supabase,
    "my_diary_list_due_unconfirmed_exchange_image_orphans",
  );
}

function parseCandidateRelation(
  value: unknown,
  reportId: string,
  maxItems: number,
) {
  const relations = Array.isArray(value) ? value : [value];

  return (
    relations.length >= 1 &&
    relations.length <= maxItems &&
    relations.every(
      (relation) =>
        typeof relation === "object" &&
        relation !== null &&
        hasExactKeys(relation, ["report_id"]) &&
        "report_id" in relation &&
        relation.report_id === reportId,
    )
  );
}

function parseCandidateRow(
  value: unknown,
  relationKey: "snapshot" | "snapshot_images",
  selectedAt: number,
): DueReportEvidenceCandidate | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, [
      "id",
      "status",
      "evidence_delete_after",
      relationKey,
    ]) ||
    !("id" in value) ||
    !("status" in value) ||
    !("evidence_delete_after" in value) ||
    !(relationKey in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    value.id !== value.id.toLowerCase() ||
    !isReportStatus(value.status) ||
    (value.status !== "resolved" && value.status !== "dismissed") ||
    typeof value.evidence_delete_after !== "string" ||
    !isPostSearchTimestamp(value.evidence_delete_after) ||
    Date.parse(value.evidence_delete_after) > selectedAt ||
    !parseCandidateRelation(
      (value as Record<string, unknown>)[relationKey],
      value.id,
      relationKey === "snapshot" ? 1 : 10,
    )
  ) {
    return null;
  }

  return {
    reportId: value.id,
    evidenceDeleteAfter: value.evidence_delete_after,
  };
}

async function loadCandidateGroup(
  supabase: SupabaseClient,
  selectedAtIso: string,
  relationKey: "snapshot" | "snapshot_images",
): Promise<DueReportEvidenceCandidateResult> {
  const select =
    relationKey === "snapshot"
      ? SNAPSHOT_CANDIDATE_SELECT
      : IMAGE_CANDIDATE_SELECT;
  let result;

  try {
    result = await supabase
      .from("reports")
      .select(select)
      .in("status", ["resolved", "dismissed"])
      .not("evidence_delete_after", "is", null)
      .lte("evidence_delete_after", selectedAtIso)
      .order("evidence_delete_after", { ascending: true })
      .order("id", { ascending: true })
      .limit(ADMIN_EVIDENCE_PURGE_BATCH_SIZE)
      .returns<unknown[]>();
  } catch {
    return { kind: "error" };
  }

  if (
    result.error ||
    !Array.isArray(result.data) ||
    result.data.length > ADMIN_EVIDENCE_PURGE_BATCH_SIZE
  ) {
    return { kind: "error" };
  }

  const selectedAt = Date.parse(selectedAtIso);
  const candidates: DueReportEvidenceCandidate[] = [];
  const reportIds = new Set<string>();

  for (const value of result.data) {
    const candidate = parseCandidateRow(value, relationKey, selectedAt);

    if (!candidate || reportIds.has(candidate.reportId)) {
      return { kind: "error" };
    }

    reportIds.add(candidate.reportId);
    candidates.push(candidate);
  }

  return { kind: "success", candidates };
}

export async function selectDueReportEvidenceCandidates(
  supabase: SupabaseClient,
): Promise<DueReportEvidenceCandidateResult> {
  const selectedAtIso = new Date().toISOString();
  const snapshotResult = await loadCandidateGroup(
    supabase,
    selectedAtIso,
    "snapshot",
  );

  if (snapshotResult.kind !== "success") {
    return snapshotResult;
  }

  const imageResult = await loadCandidateGroup(
    supabase,
    selectedAtIso,
    "snapshot_images",
  );

  if (imageResult.kind !== "success") {
    return imageResult;
  }

  const candidatesByReportId = new Map<string, DueReportEvidenceCandidate>();

  for (const candidate of [
    ...snapshotResult.candidates,
    ...imageResult.candidates,
  ]) {
    const existing = candidatesByReportId.get(candidate.reportId);

    if (
      existing &&
      existing.evidenceDeleteAfter !== candidate.evidenceDeleteAfter
    ) {
      return { kind: "error" };
    }

    candidatesByReportId.set(candidate.reportId, candidate);
  }

  const candidates = Array.from(candidatesByReportId.values())
    .sort((left, right) => {
      const dueComparison =
        Date.parse(left.evidenceDeleteAfter) -
        Date.parse(right.evidenceDeleteAfter);

      return dueComparison !== 0
        ? dueComparison
        : left.reportId.localeCompare(right.reportId);
    })
    .slice(0, ADMIN_EVIDENCE_PURGE_BATCH_SIZE);

  return { kind: "success", candidates };
}
