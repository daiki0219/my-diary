"use server";

import { revalidatePath } from "next/cache";

import {
  canTransitionAdminReportStatus,
  isAdminReportNextStatus,
} from "@/lib/admin-report-status";
import { isUuid } from "@/lib/profile-data";
import { isReportStatus } from "@/lib/report";
import { getAdminSessionState } from "@/lib/supabase/admin-session";
import { createClient } from "@/lib/supabase/server";

export type AdminReportStatusActionState =
  | { outcome: "idle"; revision: 0 }
  | {
      outcome: "success" | "stale" | "error";
      revision: number;
    };

const STATUS_FORM_FIELDS = new Set([
  "reportId",
  "expectedStatus",
  "nextStatus",
]);
const FRAMEWORK_ACTION_FIELD_PATTERN =
  /^\$ACTION_(?:(?:REF|ID)_)?\d+(?::\d+)?$/u;

function isFrameworkActionField(fieldName: string) {
  return (
    fieldName === "$ACTION_KEY" ||
    FRAMEWORK_ACTION_FIELD_PATTERN.test(fieldName)
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
  previousState: AdminReportStatusActionState,
  outcome: "success" | "stale" | "error",
): AdminReportStatusActionState {
  return { outcome, revision: nextRevision(previousState) };
}

function getStrictStatusFormValues(formData: FormData) {
  const entries = Array.from(formData.entries());
  const inputEntries = entries.filter(
    ([fieldName]) => !isFrameworkActionField(fieldName),
  );
  const frameworkEntries = entries.filter(([fieldName]) =>
    isFrameworkActionField(fieldName),
  );

  if (
    inputEntries.length !== STATUS_FORM_FIELDS.size ||
    inputEntries.some(([fieldName]) => !STATUS_FORM_FIELDS.has(fieldName)) ||
    frameworkEntries.some(([, value]) => typeof value !== "string")
  ) {
    return null;
  }

  const reportIds = formData.getAll("reportId");
  const expectedStatuses = formData.getAll("expectedStatus");
  const nextStatuses = formData.getAll("nextStatus");

  if (
    reportIds.length !== 1 ||
    expectedStatuses.length !== 1 ||
    nextStatuses.length !== 1
  ) {
    return null;
  }

  const [reportId] = reportIds;
  const [expectedStatus] = expectedStatuses;
  const [nextStatus] = nextStatuses;

  if (
    typeof reportId !== "string" ||
    !isUuid(reportId) ||
    reportId !== reportId.toLowerCase() ||
    typeof expectedStatus !== "string" ||
    !isReportStatus(expectedStatus) ||
    typeof nextStatus !== "string" ||
    !isAdminReportNextStatus(nextStatus) ||
    !canTransitionAdminReportStatus(expectedStatus, nextStatus)
  ) {
    return null;
  }

  return { reportId, expectedStatus, nextStatus };
}

export async function updateAdminReportStatus(
  previousState: AdminReportStatusActionState,
  formData: FormData,
): Promise<AdminReportStatusActionState> {
  const errorResult = () => actionState(previousState, "error");
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

  if (adminSession.kind !== "active-admin") {
    return errorResult();
  }

  const values = getStrictStatusFormValues(formData);

  if (!values) {
    return errorResult();
  }

  let result;

  try {
    result = await supabase.rpc("my_diary_update_report_status", {
      p_report_id: values.reportId,
      p_expected_status: values.expectedStatus,
      p_status: values.nextStatus,
    });
  } catch {
    return errorResult();
  }

  if (result.error || typeof result.data !== "boolean") {
    return errorResult();
  }

  if (result.data === false) {
    return actionState(previousState, "stale");
  }

  try {
    revalidatePath("/admin/reports");
    revalidatePath(`/admin/reports/${values.reportId}`);
  } catch {
    // Mutationはcommit済みなので、再検証失敗を更新失敗として返さない。
  }

  return actionState(previousState, "success");
}
