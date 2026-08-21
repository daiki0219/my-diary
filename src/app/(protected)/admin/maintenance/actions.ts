"use server";

import { revalidatePath } from "next/cache";

import {
  loadAdminMaintenanceSummary,
  selectDueReportEvidenceCandidates,
} from "@/lib/admin-maintenance-data";
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
