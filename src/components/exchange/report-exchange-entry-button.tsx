"use client";

import {
  useActionState,
  useEffect,
  useId,
  useRef,
  useState,
} from "react";

import {
  createExchangeEntryReport,
  type ExchangeEntryReportActionState,
} from "@/app/(protected)/exchange/actions";
import {
  EXCHANGE_ENTRY_REPORT_DETAILS_MAX_CODE_POINTS,
  EXCHANGE_ENTRY_REPORT_REASON_OPTIONS,
  validateExchangeEntryReportValues,
  type ExchangeEntryReportFieldErrors,
} from "@/lib/exchange-entry-report";

const initialState: ExchangeEntryReportActionState = {
  error: null,
  fieldErrors: {},
  completed: false,
  outcome: "idle",
  submittedReason: "",
  submittedDetails: "",
  revision: 0,
};

export function ReportExchangeEntryButton({
  diaryId,
  entryId,
  accessibleName,
}: {
  diaryId: string;
  entryId: string;
  accessibleName: string;
}) {
  const confirmationId = useId();
  const titleId = `${confirmationId}-title`;
  const descriptionId = `${confirmationId}-description`;
  const reasonId = `${confirmationId}-reason`;
  const reasonErrorId = `${confirmationId}-reason-error`;
  const detailsId = `${confirmationId}-details`;
  const detailsHelpId = `${confirmationId}-details-help`;
  const detailsErrorId = `${confirmationId}-details-error`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const reasonRef = useRef<HTMLSelectElement>(null);
  const detailsRef = useRef<HTMLTextAreaElement>(null);
  const successRef = useRef<HTMLParagraphElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [reason, setReason] = useState("");
  const [details, setDetails] = useState("");
  const [clientFieldErrors, setClientFieldErrors] =
    useState<ExchangeEntryReportFieldErrors | null>(null);
  const [state, formAction, isPending] = useActionState(
    createExchangeEntryReport,
    initialState,
  );
  const fieldErrors = clientFieldErrors ?? state.fieldErrors;
  const detailsCount = Array.from(details.trim()).length;
  const retryIsBlocked = state.outcome === "unknown-outcome";

  useEffect(() => {
    if (isConfirming) {
      reasonRef.current?.focus();
    }
  }, [isConfirming]);

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }
  }, [isPending, state.revision]);

  useEffect(() => {
    if (state.completed) {
      requestAnimationFrame(() => successRef.current?.focus());
    }
  }, [state.completed, state.revision]);

  function closeConfirmation() {
    setIsConfirming(false);
    setClientFieldErrors(null);
    requestAnimationFrame(() => triggerRef.current?.focus());
  }

  if (state.completed) {
    return (
      <p
        aria-atomic="true"
        aria-live="polite"
        className="text-sm font-semibold leading-6 text-emerald-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
        ref={successRef}
        role="status"
        tabIndex={-1}
      >
        通報を受け付けました
      </p>
    );
  }

  return (
    <div className="min-w-0">
      {isConfirming ? (
        <div
          aria-describedby={descriptionId}
          aria-labelledby={titleId}
          className="min-w-0 rounded-2xl border border-stone-200 bg-stone-50 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="dialog"
        >
          <p className="text-sm font-bold leading-6 text-stone-800" id={titleId}>
            この日記を通報しますか？
          </p>
          <p
            className="mt-1 text-xs leading-5 text-stone-600"
            id={descriptionId}
          >
            通報理由を選び、必要に応じて詳しい状況を入力してください。
          </p>

          <form
            action={formAction}
            className="mt-4 min-w-0 space-y-4"
            onSubmit={(event) => {
              if (submissionInFlight.current || retryIsBlocked) {
                event.preventDefault();
                return;
              }

              const validation = validateExchangeEntryReportValues(
                reason,
                details,
              );

              if (!validation.data) {
                event.preventDefault();
                setClientFieldErrors(validation.fieldErrors);
                requestAnimationFrame(() => {
                  if (validation.fieldErrors.reason) {
                    reasonRef.current?.focus();
                  } else {
                    detailsRef.current?.focus();
                  }
                });
                return;
              }

              setClientFieldErrors({});
              submissionInFlight.current = true;
            }}
          >
            <input name="diaryId" type="hidden" value={diaryId} />
            <input name="entryId" type="hidden" value={entryId} />

            <div>
              <label
                className="block text-sm font-semibold text-stone-800"
                htmlFor={reasonId}
              >
                通報理由 <span className="text-red-700">必須</span>
              </label>
              <select
                aria-describedby={fieldErrors.reason ? reasonErrorId : undefined}
                aria-invalid={Boolean(fieldErrors.reason)}
                className="mt-2 min-h-11 w-full min-w-0 rounded-xl border border-stone-300 bg-white px-3 py-2 text-sm text-stone-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                disabled={isPending || retryIsBlocked}
                id={reasonId}
                name="reason"
                onChange={(event) => {
                  setReason(event.currentTarget.value);
                  setClientFieldErrors((current) => ({
                    ...(current ?? state.fieldErrors),
                    reason: undefined,
                  }));
                }}
                ref={reasonRef}
                aria-required="true"
                value={reason}
              >
                <option value="">選択してください</option>
                {EXCHANGE_ENTRY_REPORT_REASON_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
              {fieldErrors.reason && (
                <p
                  className="mt-2 text-xs leading-5 text-red-700"
                  id={reasonErrorId}
                  role="alert"
                >
                  {fieldErrors.reason}
                </p>
              )}
            </div>

            <div>
              <label
                className="block text-sm font-semibold text-stone-800"
                htmlFor={detailsId}
              >
                詳細
              </label>
              <textarea
                aria-describedby={`${detailsHelpId}${fieldErrors.details ? ` ${detailsErrorId}` : ""}`}
                aria-invalid={Boolean(fieldErrors.details)}
                className="mt-2 min-h-32 w-full min-w-0 resize-y rounded-xl border border-stone-300 bg-white px-3 py-2 text-sm leading-6 text-stone-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                disabled={isPending || retryIsBlocked}
                id={detailsId}
                name="details"
                onChange={(event) => {
                  setDetails(event.currentTarget.value);
                  setClientFieldErrors((current) => ({
                    ...(current ?? state.fieldErrors),
                    details: undefined,
                  }));
                }}
                ref={detailsRef}
                rows={5}
                value={details}
              />
              <div
                className="mt-1 flex min-w-0 flex-col gap-1 text-xs leading-5 text-stone-500 sm:flex-row sm:justify-between"
                id={detailsHelpId}
              >
                <p className="min-w-0 break-words">
                  2,000文字まで入力できます。「その他」を選んだ場合は必須です。
                </p>
                <p
                  aria-hidden="true"
                  className={
                    detailsCount >
                    EXCHANGE_ENTRY_REPORT_DETAILS_MAX_CODE_POINTS
                      ? "shrink-0 font-semibold text-red-700"
                      : "shrink-0"
                  }
                >
                  {detailsCount.toLocaleString("ja-JP")} / 2,000文字
                </p>
              </div>
              {fieldErrors.details && (
                <p
                  className="mt-2 text-xs leading-5 text-red-700"
                  id={detailsErrorId}
                  role="alert"
                >
                  {fieldErrors.details}
                </p>
              )}
            </div>

            <div className="grid gap-2 sm:grid-cols-2">
              <button
                aria-disabled={isPending || retryIsBlocked}
                className="min-h-11 w-full rounded-full bg-red-700 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:bg-stone-400"
                disabled={isPending || retryIsBlocked}
                type="submit"
              >
                {isPending ? "送信中…" : "通報を送信する"}
              </button>
              <button
                aria-disabled={isPending}
                className="min-h-11 w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 text-sm font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60"
                disabled={isPending}
                onClick={closeConfirmation}
                type="button"
              >
                キャンセル
              </button>
            </div>
          </form>

          <p aria-live="polite" className="sr-only">
            {isPending ? "通報を送信しています" : ""}
          </p>
          {state.error && (
            <p
              className="mt-3 rounded-xl border border-red-200 bg-white px-3 py-2 text-xs leading-5 text-red-700"
              key={state.revision}
              role="alert"
            >
              {state.error}
            </p>
          )}
        </div>
      ) : (
        <button
          aria-controls={confirmationId}
          aria-expanded={isConfirming}
          aria-label={accessibleName}
          className="inline-flex min-h-10 items-center rounded-full border border-stone-300 bg-white px-4 py-2 text-xs font-semibold text-stone-600 transition hover:border-red-300 hover:bg-red-50 hover:text-red-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
          onClick={() => setIsConfirming(true)}
          ref={triggerRef}
          type="button"
        >
          この日記を通報
        </button>
      )}
    </div>
  );
}
