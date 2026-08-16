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
  createExchangeUserReport,
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

type ExchangeReportButtonProps = {
  diaryId: string;
  accessibleName: string;
} & (
  | {
      kind: "entry";
      entryId: string;
    }
  | {
      kind: "user";
      counterpartName: string;
      relatedEntryId?: string;
    }
);

function ExchangeReportButton({
  diaryId,
  accessibleName,
  ...target
}: ExchangeReportButtonProps) {
  const confirmationId = useId();
  const titleId = `${confirmationId}-title`;
  const descriptionId = `${confirmationId}-description`;
  const reasonId = `${confirmationId}-reason`;
  const reasonErrorId = `${confirmationId}-reason-error`;
  const detailsId = `${confirmationId}-details`;
  const detailsHelpId = `${confirmationId}-details-help`;
  const detailsErrorId = `${confirmationId}-details-error`;
  const relatedEntryId = `${confirmationId}-related-entry`;
  const relatedEntryHelpId = `${confirmationId}-related-entry-help`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const reasonRef = useRef<HTMLSelectElement>(null);
  const detailsRef = useRef<HTMLTextAreaElement>(null);
  const successRef = useRef<HTMLParagraphElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [reason, setReason] = useState("");
  const [details, setDetails] = useState("");
  const [includeRelatedEntry, setIncludeRelatedEntry] = useState(false);
  const [clientFieldErrors, setClientFieldErrors] =
    useState<ExchangeEntryReportFieldErrors | null>(null);
  const [handledRevision, setHandledRevision] = useState(0);
  const [state, formAction, isPending] = useActionState(
    target.kind === "entry"
      ? createExchangeEntryReport
      : createExchangeUserReport,
    initialState,
  );

  if (state.revision !== handledRevision) {
    setHandledRevision(state.revision);
    setClientFieldErrors(null);
    setReason(state.submittedReason);
    setDetails(state.submittedDetails);
  }

  const fieldErrors = clientFieldErrors ?? state.fieldErrors;
  const detailsCount = Array.from(details.trim()).length;
  const retryIsBlocked = state.outcome === "unknown-outcome";
  const isUserReport = target.kind === "user";

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
            {isUserReport
              ? `${target.counterpartName}さんを通報しますか？`
              : "この日記を通報しますか？"}
          </p>
          <p
            className="mt-1 text-xs leading-5 text-stone-600"
            id={descriptionId}
          >
            {isUserReport
              ? "この交換日記の相手について運営へ報告します。通報理由を選び、必要に応じて詳しい状況を入力してください。"
              : "この日記そのものについて運営へ報告します。通報理由を選び、必要に応じて詳しい状況を入力してください。"}
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
            {target.kind === "entry" && (
              <input name="entryId" type="hidden" value={target.entryId} />
            )}
            {target.kind === "user" &&
              target.relatedEntryId &&
              includeRelatedEntry && (
                <input
                  name="relatedEntryId"
                  type="hidden"
                  value={target.relatedEntryId}
                />
              )}

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

            {target.kind === "user" && target.relatedEntryId && (
              <div className="rounded-xl border border-stone-200 bg-white p-3">
                <label
                  className="flex min-h-11 cursor-pointer items-start gap-3 text-sm font-semibold leading-6 text-stone-800"
                  htmlFor={relatedEntryId}
                >
                  <input
                    aria-describedby={relatedEntryHelpId}
                    checked={includeRelatedEntry}
                    className="mt-1.5 h-4 w-4 shrink-0 accent-red-700"
                    disabled={isPending || retryIsBlocked}
                    id={relatedEntryId}
                    onChange={(event) =>
                      setIncludeRelatedEntry(event.currentTarget.checked)
                    }
                    type="checkbox"
                  />
                  <span className="min-w-0 break-words">
                    この日記を関連情報として添付する
                  </span>
                </label>
                <p
                  className="mt-1 pl-7 text-xs leading-5 text-stone-600"
                  id={relatedEntryHelpId}
                >
                  選択すると、現在表示している相手の日記1件だけを通報時点の関連情報として添付します。
                </p>
              </div>
            )}

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
          {isUserReport ? "このユーザーを通報" : "この日記を通報"}
        </button>
      )}
    </div>
  );
}

export function ReportExchangeEntryButton({
  diaryId,
  entryId,
  accessibleName,
}: {
  diaryId: string;
  entryId: string;
  accessibleName: string;
}) {
  return (
    <ExchangeReportButton
      accessibleName={accessibleName}
      diaryId={diaryId}
      entryId={entryId}
      kind="entry"
    />
  );
}

export function ReportExchangeUserButton({
  diaryId,
  counterpartName,
  relatedEntryId,
  accessibleName,
}: {
  diaryId: string;
  counterpartName: string;
  relatedEntryId?: string;
  accessibleName: string;
}) {
  return (
    <ExchangeReportButton
      accessibleName={accessibleName}
      counterpartName={counterpartName}
      diaryId={diaryId}
      kind="user"
      relatedEntryId={relatedEntryId}
    />
  );
}
