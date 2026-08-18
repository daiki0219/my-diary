"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useId, useRef, useState } from "react";

import {
  updateAdminReportStatus,
  type AdminReportStatusActionState,
} from "@/app/(protected)/admin/reports/actions";
import {
  getAdminReportStatusTransitions,
  type AdminReportNextStatus,
} from "@/lib/admin-report-status";
import {
  REPORT_STATUS_LABELS,
  type ReportStatus,
} from "@/lib/report";

const initialState: AdminReportStatusActionState = {
  outcome: "idle",
  revision: 0,
};

const actionLabels = {
  reviewing: "確認中にする",
  resolved: "対応済みにする",
  dismissed: "却下する",
} as const satisfies Record<AdminReportNextStatus, string>;

function isTerminalStatus(
  status: AdminReportNextStatus,
): status is "resolved" | "dismissed" {
  return status === "resolved" || status === "dismissed";
}

export function AdminReportStatusActions({
  reportId,
  currentStatus,
}: {
  reportId: string;
  currentStatus: ReportStatus;
}) {
  const router = useRouter();
  const confirmationId = useId();
  const confirmationTitleId = `${confirmationId}-title`;
  const confirmationDescriptionId = `${confirmationId}-description`;
  const resolvedTriggerRef = useRef<HTMLButtonElement>(null);
  const dismissedTriggerRef = useRef<HTMLButtonElement>(null);
  const lastTerminalStatusRef =
    useRef<"resolved" | "dismissed" | null>(null);
  const cancelRef = useRef<HTMLButtonElement>(null);
  const feedbackRef = useRef<HTMLDivElement>(null);
  const submissionInFlight = useRef(false);
  const [terminalStatus, setTerminalStatus] =
    useState<"resolved" | "dismissed" | null>(null);
  const [state, formAction, isPending] = useActionState(
    updateAdminReportStatus,
    initialState,
  );
  const transitions = getAdminReportStatusTransitions(currentStatus);

  useEffect(() => {
    if (terminalStatus) {
      cancelRef.current?.focus();
    }
  }, [terminalStatus]);

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }

    if (isPending || state.outcome === "idle") {
      return;
    }

    if (state.outcome === "success") {
      router.refresh();
    }

    const frame = requestAnimationFrame(() => {
      setTerminalStatus(null);
      requestAnimationFrame(() => feedbackRef.current?.focus());
    });

    return () => cancelAnimationFrame(frame);
  }, [isPending, router, state.outcome, state.revision]);

  function closeConfirmation() {
    const lastTerminalStatus = lastTerminalStatusRef.current;
    setTerminalStatus(null);
    requestAnimationFrame(() => {
      if (lastTerminalStatus === "resolved") {
        resolvedTriggerRef.current?.focus();
      } else if (lastTerminalStatus === "dismissed") {
        dismissedTriggerRef.current?.focus();
      }
    });
  }

  function openConfirmation(
    nextStatus: "resolved" | "dismissed",
  ) {
    if (isPending || submissionInFlight.current) {
      return;
    }

    lastTerminalStatusRef.current = nextStatus;
    setTerminalStatus(nextStatus);
  }

  function preventDuplicateSubmission(event: React.FormEvent<HTMLFormElement>) {
    if (isPending || submissionInFlight.current) {
      event.preventDefault();
      return;
    }

    submissionInFlight.current = true;
  }

  const feedback =
    state.outcome === "success"
      ? "状態を更新しました。"
      : state.outcome === "stale"
        ? "この通報の状態が更新されています。最新の状態を確認してください。"
        : state.outcome === "error"
          ? "状態を更新できませんでした。画面を再読み込みして、もう一度お試しください。"
          : null;

  return (
    <section
      aria-labelledby="report-status-actions-heading"
      className="mt-5 min-w-0 rounded-3xl border border-orange-200 bg-orange-50 p-5 sm:p-6"
    >
      <h2
        className="text-xl font-bold text-stone-800"
        id="report-status-actions-heading"
      >
        対応状況
      </h2>
      <p className="mt-3 text-sm leading-6 text-stone-700">
        現在の状態：
        <strong className="font-bold text-stone-900">
          {REPORT_STATUS_LABELS[currentStatus]}
        </strong>
      </p>

      {!isPending && feedback && (
        <div
          aria-atomic="true"
          aria-live={state.outcome === "success" ? "polite" : "assertive"}
          className={
            state.outcome === "success"
              ? "mt-4 min-w-0 rounded-2xl border border-emerald-200 bg-white p-4 text-sm leading-6 text-emerald-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
              : "mt-4 min-w-0 rounded-2xl border border-red-200 bg-white p-4 text-sm leading-6 text-red-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
          }
          key={state.revision}
          ref={feedbackRef}
          role={state.outcome === "success" ? "status" : "alert"}
          tabIndex={-1}
        >
          <p className="break-words [overflow-wrap:anywhere]">{feedback}</p>
          {state.outcome !== "success" && (
            <button
              className="mt-3 min-h-11 w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-800 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-700 sm:w-auto"
              onClick={() => router.refresh()}
              type="button"
            >
              最新の状態を確認
            </button>
          )}
        </div>
      )}

      {transitions.length === 0 ? (
        <p className="mt-4 rounded-2xl bg-white p-4 text-sm leading-6 text-stone-600">
          この通報の対応は完了しています。
        </p>
      ) : terminalStatus ? (
        <div
          aria-describedby={confirmationDescriptionId}
          aria-labelledby={confirmationTitleId}
          className="mt-4 min-w-0 rounded-2xl border border-red-200 bg-red-50 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="alertdialog"
        >
          <h3
            className="break-words text-base font-bold leading-6 text-stone-800 [overflow-wrap:anywhere]"
            id={confirmationTitleId}
          >
            この通報を「{REPORT_STATUS_LABELS[terminalStatus]}」にしますか？
          </h3>
          <p
            className="mt-2 break-words text-sm leading-6 text-stone-700 [overflow-wrap:anywhere]"
            id={confirmationDescriptionId}
          >
            この操作後、通報の状態を未対応・確認中へ戻すことはできません。
          </p>

          <form
            action={formAction}
            className="mt-4 grid min-w-0 gap-2 sm:grid-cols-2"
            onSubmit={preventDuplicateSubmission}
          >
            <input name="reportId" type="hidden" value={reportId} />
            <input
              name="expectedStatus"
              type="hidden"
              value={currentStatus}
            />
            <input
              name="nextStatus"
              type="hidden"
              value={terminalStatus}
            />
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full bg-red-700 px-4 py-2.5 font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:bg-stone-400 [overflow-wrap:anywhere]"
              disabled={isPending}
              type="submit"
            >
              {isPending ? "処理中…" : actionLabels[terminalStatus]}
            </button>
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60 [overflow-wrap:anywhere]"
              disabled={isPending}
              onClick={closeConfirmation}
              ref={cancelRef}
              type="button"
            >
              キャンセル
            </button>
          </form>
        </div>
      ) : (
        <div className="mt-4 grid min-w-0 gap-2 sm:grid-cols-2">
          {transitions.map((nextStatus) =>
            isTerminalStatus(nextStatus) ? (
              <button
                aria-controls={confirmationId}
                aria-expanded={terminalStatus === nextStatus}
                className={
                  nextStatus === "dismissed"
                    ? "min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full border border-red-300 bg-white px-4 py-2.5 font-semibold text-red-700 transition hover:bg-red-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:opacity-60 [overflow-wrap:anywhere]"
                    : "min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full bg-orange-700 px-4 py-2.5 font-semibold text-white transition hover:bg-orange-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700 disabled:cursor-wait disabled:bg-stone-400 [overflow-wrap:anywhere]"
                }
                disabled={isPending}
                key={nextStatus}
                onClick={() => openConfirmation(nextStatus)}
                ref={
                  nextStatus === "resolved"
                    ? resolvedTriggerRef
                    : dismissedTriggerRef
                }
                type="button"
              >
                {actionLabels[nextStatus]}
              </button>
            ) : (
              <form
                action={formAction}
                className="min-w-0"
                key={nextStatus}
                onSubmit={preventDuplicateSubmission}
              >
                <input name="reportId" type="hidden" value={reportId} />
                <input
                  name="expectedStatus"
                  type="hidden"
                  value={currentStatus}
                />
                <input
                  name="nextStatus"
                  type="hidden"
                  value={nextStatus}
                />
                <button
                  aria-disabled={isPending}
                  className="min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full border border-orange-300 bg-white px-4 py-2.5 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-700 disabled:cursor-wait disabled:opacity-60 [overflow-wrap:anywhere]"
                  disabled={isPending}
                  type="submit"
                >
                  {isPending ? "処理中…" : actionLabels[nextStatus]}
                </button>
              </form>
            ),
          )}
        </div>
      )}

      <p aria-atomic="true" aria-live="polite" className="sr-only" role="status">
        {isPending ? "通報の状態を更新しています" : ""}
      </p>
    </section>
  );
}
