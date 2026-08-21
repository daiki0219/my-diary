"use server";

import type { SupabaseClient } from "@supabase/supabase-js";
import { revalidatePath } from "next/cache";

import {
  listDueConfirmedExchangeImageCleanupCandidates,
  listDueUnconfirmedExchangeImageOrphans,
  loadAdminMaintenanceSummary,
  selectDueReportEvidenceCandidates,
} from "@/lib/admin-maintenance-data";
import { EXCHANGE_ENTRY_IMAGE_BUCKET } from "@/lib/exchange-entry-image-input";
import { getAdminSessionState } from "@/lib/supabase/admin-session";
import { createClient } from "@/lib/supabase/server";

export type AdminEvidencePurgeActionState = {
  outcome:
    | "idle"
    | "success"
    | "empty"
    | "changed"
    | "partial"
    | "unknown"
    | "error";
  revision: number;
  selected: number;
  processed: number;
  unavailable: number;
  failed: number;
  unknown: number;
  remainingDue: number | null;
};

export type AdminExchangeImageCleanupActionState = {
  outcome:
    | "idle"
    | "success"
    | "empty"
    | "changed"
    | "partial"
    | "unknown"
    | "error";
  revision: number;
  selected: number;
  processed: number;
  reconciled: number;
  unavailable: number;
  failed: number;
  unknown: number;
  remainingDue: number | null;
};

const FRAMEWORK_ACTION_FIELD_PATTERN =
  /^\$ACTION_(?:(?:REF|ID)_)?\d+(?::\d+)?$/u;

function isFrameworkActionField(fieldName: string) {
  return (
    fieldName === "$ACTION_KEY" ||
    FRAMEWORK_ACTION_FIELD_PATTERN.test(fieldName)
  );
}

function hasNoApplicationInput(formData: FormData) {
  return Array.from(formData.entries()).every(
    ([fieldName, value]) =>
      isFrameworkActionField(fieldName) && typeof value === "string",
  );
}

function nextRevision(previousState: unknown) {
  const revision =
    typeof previousState === "object" &&
    previousState !== null &&
    "revision" in previousState
      ? previousState.revision
      : null;

  return typeof revision === "number" &&
    Number.isSafeInteger(revision) &&
    revision >= 0 &&
    revision < Number.MAX_SAFE_INTEGER
    ? revision + 1
    : 1;
}

function actionState(
  previousState: AdminEvidencePurgeActionState,
  values: Omit<AdminEvidencePurgeActionState, "revision">,
): AdminEvidencePurgeActionState {
  return { ...values, revision: nextRevision(previousState) };
}

function emptyCounts() {
  return {
    selected: 0,
    processed: 0,
    unavailable: 0,
    failed: 0,
    unknown: 0,
  };
}

function imageActionState(
  previousState: AdminExchangeImageCleanupActionState,
  values: Omit<AdminExchangeImageCleanupActionState, "revision">,
): AdminExchangeImageCleanupActionState {
  return { ...values, revision: nextRevision(previousState) };
}

function emptyImageCounts() {
  return {
    selected: 0,
    processed: 0,
    reconciled: 0,
    unavailable: 0,
    failed: 0,
    unknown: 0,
  };
}

type StorageRemoveOutcome =
  | "deleted"
  | "zero-row"
  | "unavailable"
  | "failed"
  | "unknown";

async function removeExchangeEntryImage(
  supabase: SupabaseClient,
  storagePath: string,
): Promise<StorageRemoveOutcome> {
  let result;

  try {
    result = await supabase.storage
      .from(EXCHANGE_ENTRY_IMAGE_BUCKET)
      .remove([storagePath]);
  } catch {
    return "unknown";
  }

  if (result.error) {
    if (result.error.status === undefined) {
      return "unknown";
    }

    return result.error.status === 401 || result.error.status === 403
      ? "unavailable"
      : "failed";
  }

  if (!Array.isArray(result.data)) {
    return "unknown";
  }

  if (result.data.length === 0) {
    return "zero-row";
  }

  if (
    result.data.length !== 1 ||
    typeof result.data[0] !== "object" ||
    result.data[0] === null ||
    result.data[0].name !== storagePath
  ) {
    return "unknown";
  }

  return "deleted";
}

type CompletionOutcome =
  | "completed"
  | "rejected"
  | "unavailable"
  | "failed"
  | "unknown";

async function completeConfirmedExchangeImageCleanup(
  supabase: SupabaseClient,
  storagePath: string,
): Promise<CompletionOutcome> {
  let result;

  try {
    result = await supabase.rpc(
      "my_diary_complete_exchange_image_cleanup",
      { p_storage_path: storagePath },
    );
  } catch {
    return "unknown";
  }

  if (result.error) {
    if (result.status === 0) {
      return "unknown";
    }

    return result.error.code === "42501" ? "unavailable" : "failed";
  }

  if (result.data === true) {
    return "completed";
  }

  return result.data === false ? "rejected" : "unknown";
}

function cleanupOutcome({
  unavailable,
  failed,
  unknown,
  stoppedAfterReconciledUnknown,
}: {
  unavailable: number;
  failed: number;
  unknown: number;
  stoppedAfterReconciledUnknown?: boolean;
}): AdminExchangeImageCleanupActionState["outcome"] {
  if (unknown > 0) {
    return "unknown";
  }

  if (unavailable > 0 || failed > 0) {
    return "partial";
  }

  return stoppedAfterReconciledUnknown ? "changed" : "success";
}

async function createImageCleanupActionContext(
  formData: FormData,
): Promise<
  | { kind: "success"; supabase: SupabaseClient }
  | { kind: "error" }
> {
  let supabase;

  try {
    supabase = await createClient();
  } catch {
    return { kind: "error" };
  }

  let adminSession;

  try {
    adminSession = await getAdminSessionState(supabase);
  } catch {
    return { kind: "error" };
  }

  return adminSession.kind === "active-admin" && hasNoApplicationInput(formData)
    ? { kind: "success", supabase }
    : { kind: "error" };
}

export async function cleanupConfirmedExchangeImages(
  previousState: AdminExchangeImageCleanupActionState,
  formData: FormData,
): Promise<AdminExchangeImageCleanupActionState> {
  const errorResult = () =>
    imageActionState(previousState, {
      outcome: "error",
      ...emptyImageCounts(),
      remainingDue: null,
    });
  const context = await createImageCleanupActionContext(formData);

  if (context.kind !== "success") {
    return errorResult();
  }

  const { supabase } = context;
  const initialSummary = await loadAdminMaintenanceSummary(supabase);

  if (initialSummary.kind !== "success") {
    return errorResult();
  }

  if (initialSummary.summary.dueConfirmedCleanupCandidateCount === 0) {
    return imageActionState(previousState, {
      outcome: "empty",
      ...emptyImageCounts(),
      remainingDue: 0,
    });
  }

  const candidateResult =
    await listDueConfirmedExchangeImageCleanupCandidates(supabase);

  if (candidateResult.kind !== "success") {
    return errorResult();
  }

  if (candidateResult.storagePaths.length === 0) {
    const refreshedSummary = await loadAdminMaintenanceSummary(supabase);

    return imageActionState(previousState, {
      outcome: "changed",
      ...emptyImageCounts(),
      remainingDue:
        refreshedSummary.kind === "success"
          ? refreshedSummary.summary.dueConfirmedCleanupCandidateCount
          : null,
    });
  }

  let processed = 0;
  let reconciled = 0;
  let unavailable = 0;
  let failed = 0;
  let unknown = 0;
  let stoppedAfterReconciledUnknown = false;

  for (const storagePath of candidateResult.storagePaths) {
    const removeOutcome = await removeExchangeEntryImage(supabase, storagePath);

    if (removeOutcome === "unavailable") {
      unavailable += 1;
      break;
    }

    if (removeOutcome === "failed") {
      failed += 1;
      break;
    }

    if (removeOutcome === "unknown") {
      const completionOutcome = await completeConfirmedExchangeImageCleanup(
        supabase,
        storagePath,
      );

      if (completionOutcome === "completed") {
        reconciled += 1;
        stoppedAfterReconciledUnknown = true;
      } else {
        unknown += 1;
      }
      break;
    }

    const completionOutcome = await completeConfirmedExchangeImageCleanup(
      supabase,
      storagePath,
    );

    if (completionOutcome === "completed") {
      if (removeOutcome === "deleted") {
        processed += 1;
      } else {
        reconciled += 1;
      }
      continue;
    }

    if (
      completionOutcome === "rejected" ||
      completionOutcome === "unavailable"
    ) {
      unavailable += 1;
    } else if (completionOutcome === "failed") {
      failed += 1;
    } else {
      unknown += 1;
    }
    break;
  }

  const refreshedSummary = await loadAdminMaintenanceSummary(supabase);
  const remainingDue =
    refreshedSummary.kind === "success"
      ? refreshedSummary.summary.dueConfirmedCleanupCandidateCount
      : null;

  try {
    revalidatePath("/admin/maintenance");
  } catch {
    // Cleanup結果は確定済みなので、再検証失敗を処理失敗として返さない。
  }

  return imageActionState(previousState, {
    outcome: cleanupOutcome({
      unavailable,
      failed,
      unknown,
      stoppedAfterReconciledUnknown,
    }),
    selected: candidateResult.storagePaths.length,
    processed,
    reconciled,
    unavailable,
    failed,
    unknown,
    remainingDue,
  });
}

export async function cleanupUnconfirmedExchangeImageOrphans(
  previousState: AdminExchangeImageCleanupActionState,
  formData: FormData,
): Promise<AdminExchangeImageCleanupActionState> {
  const errorResult = () =>
    imageActionState(previousState, {
      outcome: "error",
      ...emptyImageCounts(),
      remainingDue: null,
    });
  const context = await createImageCleanupActionContext(formData);

  if (context.kind !== "success") {
    return errorResult();
  }

  const { supabase } = context;
  const initialSummary = await loadAdminMaintenanceSummary(supabase);

  if (initialSummary.kind !== "success") {
    return errorResult();
  }

  if (initialSummary.summary.dueUnconfirmedOrphanCount === 0) {
    return imageActionState(previousState, {
      outcome: "empty",
      ...emptyImageCounts(),
      remainingDue: 0,
    });
  }

  const candidateResult =
    await listDueUnconfirmedExchangeImageOrphans(supabase);

  if (candidateResult.kind !== "success") {
    return errorResult();
  }

  if (candidateResult.storagePaths.length === 0) {
    const refreshedSummary = await loadAdminMaintenanceSummary(supabase);

    return imageActionState(previousState, {
      outcome: "changed",
      ...emptyImageCounts(),
      remainingDue:
        refreshedSummary.kind === "success"
          ? refreshedSummary.summary.dueUnconfirmedOrphanCount
          : null,
    });
  }

  let processed = 0;
  let unavailable = 0;
  let failed = 0;
  let unknown = 0;

  for (const storagePath of candidateResult.storagePaths) {
    const removeOutcome = await removeExchangeEntryImage(supabase, storagePath);

    if (removeOutcome === "deleted") {
      processed += 1;
      continue;
    }

    if (removeOutcome === "zero-row" || removeOutcome === "unavailable") {
      unavailable += 1;
    } else if (removeOutcome === "failed") {
      failed += 1;
    } else {
      unknown += 1;
    }
    break;
  }

  const refreshedSummary = await loadAdminMaintenanceSummary(supabase);
  const remainingDue =
    refreshedSummary.kind === "success"
      ? refreshedSummary.summary.dueUnconfirmedOrphanCount
      : null;

  try {
    revalidatePath("/admin/maintenance");
  } catch {
    // Cleanup結果は確定済みなので、再検証失敗を処理失敗として返さない。
  }

  return imageActionState(previousState, {
    outcome: cleanupOutcome({ unavailable, failed, unknown }),
    selected: candidateResult.storagePaths.length,
    processed,
    reconciled: 0,
    unavailable,
    failed,
    unknown,
    remainingDue,
  });
}

export async function purgeExpiredReportEvidence(
  previousState: AdminEvidencePurgeActionState,
  formData: FormData,
): Promise<AdminEvidencePurgeActionState> {
  const errorResult = () =>
    actionState(previousState, {
      outcome: "error",
      ...emptyCounts(),
      remainingDue: null,
    });
  let supabase;

  try {
    supabase = await createClient();
  } catch {
    return errorResult();
  }

  let adminSession;

  try {
    adminSession = await getAdminSessionState(supabase);
  } catch {
    return errorResult();
  }

  if (
    adminSession.kind !== "active-admin" ||
    !hasNoApplicationInput(formData)
  ) {
    return errorResult();
  }

  const initialSummary = await loadAdminMaintenanceSummary(supabase);

  if (initialSummary.kind !== "success") {
    return errorResult();
  }

  if (initialSummary.summary.dueReportEvidenceCount === 0) {
    return actionState(previousState, {
      outcome: "empty",
      ...emptyCounts(),
      remainingDue: 0,
    });
  }

  const candidateResult = await selectDueReportEvidenceCandidates(supabase);

  if (candidateResult.kind !== "success") {
    return errorResult();
  }

  if (candidateResult.candidates.length === 0) {
    const refreshedSummary = await loadAdminMaintenanceSummary(supabase);

    return actionState(previousState, {
      outcome: "changed",
      ...emptyCounts(),
      remainingDue:
        refreshedSummary.kind === "success"
          ? refreshedSummary.summary.dueReportEvidenceCount
          : null,
    });
  }

  let processed = 0;
  let unavailable = 0;
  let failed = 0;
  let unknown = 0;

  for (const candidate of candidateResult.candidates) {
    let result;

    try {
      result = await supabase.rpc(
        "my_diary_purge_expired_report_evidence",
        { p_report_id: candidate.reportId },
      );
    } catch {
      unknown += 1;
      break;
    }

    if (result.error) {
      if (result.status === 0) {
        unknown += 1;
      } else if (result.error.code === "42501") {
        unavailable += 1;
      } else {
        failed += 1;
      }
      break;
    }

    if (result.data !== true) {
      unknown += 1;
      break;
    }

    processed += 1;
  }

  const refreshedSummary = await loadAdminMaintenanceSummary(supabase);
  const remainingDue =
    refreshedSummary.kind === "success"
      ? refreshedSummary.summary.dueReportEvidenceCount
      : null;

  try {
    revalidatePath("/admin/maintenance");
    revalidatePath("/admin/reports");

    for (const candidate of candidateResult.candidates) {
      revalidatePath(`/admin/reports/${candidate.reportId}`);
    }
  } catch {
    // Purge結果は確定済みなので、再検証失敗を処理失敗として返さない。
  }

  const outcome =
    unknown > 0
      ? "unknown"
      : unavailable > 0 || failed > 0
        ? "partial"
        : "success";

  return actionState(previousState, {
    outcome,
    selected: candidateResult.candidates.length,
    processed,
    unavailable,
    failed,
    unknown,
    remainingDue,
  });
}
