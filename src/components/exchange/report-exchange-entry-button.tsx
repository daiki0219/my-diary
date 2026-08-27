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
  const reasonHelpId = `${confirmationId}-reason-help`;
  const reasonErrorId = `${confirmationId}-reason-error`;
  const detailsId = `${confirmationId}-details`;
  const detailsHelpId = `${confirmationId}-details-help`;
  const detailsErrorId = `${confirmationId}-details-error`;
  const relatedEntryId = `${confirmationId}-related-entry`;
  const relatedEntryHelpId = `${confirmationId}-related-entry-help`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const reasonRef = useRef<HTMLSelectElement>(null);
  const detailsRef = useRef<HTMLTextAreaElement>(null);
  const successRef = useRef<HTMLDivElement>(null);
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
      <div
        aria-atomic="true"
        aria-live="polite"
        className="min-w-0 basis-full rounded-control border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm leading-6 text-emerald-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
        ref={successRef}
        role="status"
        tabIndex={-1}
      >
        <p className="font-semibold">通報を受け付けました</p>
        <p className="mt-1 text-emerald-800">
          内容を運営へ送りました。追加の操作は必要ありません。
        </p>
      </div>
    );
  }

  return (
    <div className={isConfirming ? "min-w-0 basis-full" : "min-w-0"}>
      {isConfirming ? (
        <div
          aria-describedby={descriptionId}
          aria-labelledby={titleId}
          className="min-w-0 rounded-control border border-border-subtle bg-surface-muted/70 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="dialog"
        >
          <h3
            className="break-words text-base font-semibold leading-6 text-text-primary [overflow-wrap:anywhere]"
            id={titleId}
          >
            {isUserReport
              ? `${target.counterpartName}さんについて通報`
              : "この日記を通報"}
          </h3>
          <p
            className="mt-2 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]"
            id={descriptionId}
          >
            {isUserReport
              ? `${target.counterpartName}さんについて、問題を運営へ知らせることができます。日記そのものの通報とは別の操作です。相手には、あなたが通報したことは表示されません。`
              : "問題のある内容を運営へ知らせることができます。相手には、あなたが通報したことは表示されません。"}
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
                className="block text-sm font-semibold text-text-primary"
                htmlFor={reasonId}
              >
                通報する理由
                <span className="ml-2 text-xs font-medium text-danger">必須</span>
              </label>
              <p
                className="mt-1 text-xs leading-5 text-text-muted"
                id={reasonHelpId}
              >
                問題に最も近い理由を選んでください。
              </p>
              <select
                aria-describedby={`${reasonHelpId}${fieldErrors.reason ? ` ${reasonErrorId}` : ""}`}
                aria-invalid={Boolean(fieldErrors.reason)}
                className="mt-2 min-h-11 w-full min-w-0 rounded-control border border-border-control bg-surface-elevated px-3 py-2 text-base text-text-primary focus:border-focus focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-control-disabled-text"
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
                  className="mt-2 text-sm leading-6 text-danger"
                  id={reasonErrorId}
                  role="alert"
                >
                  {fieldErrors.reason}
                </p>
              )}
            </div>

            <div>
              <label
                className="block text-sm font-semibold text-text-primary"
                htmlFor={detailsId}
              >
                詳しい状況
                <span className="ml-2 text-xs font-medium text-text-muted">
                  「その他」以外は任意
                </span>
              </label>
              <textarea
                aria-describedby={`${detailsHelpId}${fieldErrors.details ? ` ${detailsErrorId}` : ""}`}
                aria-invalid={Boolean(fieldErrors.details)}
                className="mt-2 min-h-32 w-full min-w-0 resize-y rounded-control border border-border-control bg-surface-elevated px-3 py-2 text-base leading-7 text-text-primary focus:border-focus focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-control-disabled-text"
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
                className="mt-1 flex min-w-0 flex-col gap-1 text-xs leading-5 text-text-muted sm:flex-row sm:justify-between"
                id={detailsHelpId}
              >
                <p className="min-w-0 break-words">
                  必要な補足を2,000文字まで入力できます。「その他」を選んだ場合は必須です。
                </p>
                <p
                  aria-hidden="true"
                  className={
                    detailsCount >
                    EXCHANGE_ENTRY_REPORT_DETAILS_MAX_CODE_POINTS
                      ? "shrink-0 font-semibold text-danger"
                      : "shrink-0"
                  }
                >
                  {detailsCount.toLocaleString("ja-JP")} / 2,000文字
                </p>
              </div>
              {fieldErrors.details && (
                <p
                  className="mt-2 text-sm leading-6 text-danger"
                  id={detailsErrorId}
                  role="alert"
                >
                  {fieldErrors.details}
                </p>
              )}
            </div>

            {target.kind === "user" && target.relatedEntryId && (
              <div className="rounded-control border border-border-subtle bg-surface-elevated p-3">
                <p className="text-sm font-semibold text-text-primary">
                  参考の日記 <span className="text-xs font-medium text-text-muted">任意</span>
                </p>
                <label
                  className="mt-2 flex min-h-11 cursor-pointer items-start gap-3 text-sm font-medium leading-6 text-text-primary"
                  htmlFor={relatedEntryId}
                >
                  <input
                    aria-describedby={relatedEntryHelpId}
                    checked={includeRelatedEntry}
                    className="mt-1.5 h-4 w-4 shrink-0 accent-danger"
                    disabled={isPending || retryIsBlocked}
                    id={relatedEntryId}
                    onChange={(event) =>
                      setIncludeRelatedEntry(event.currentTarget.checked)
                    }
                    type="checkbox"
                  />
                  <span className="min-w-0 break-words">
                    この日記を通報内容の参考として伝える
                  </span>
                </label>
                <p
                  className="mt-1 pl-7 text-xs leading-5 text-text-secondary"
                  id={relatedEntryHelpId}
                >
                  選択すると、現在表示している相手の日記1件を通報時点の関連情報として運営へ伝えます。選択しなくても通報できます。
                </p>
              </div>
            )}

            <div className="grid gap-2 sm:grid-cols-2">
              <button
                aria-disabled={isPending || retryIsBlocked}
                className="min-h-11 w-full rounded-control bg-danger px-4 py-2.5 text-sm font-semibold text-white transition hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
                disabled={isPending || retryIsBlocked}
                type="submit"
              >
                {isPending ? "送信中…" : "通報を送信する"}
              </button>
              <button
                aria-disabled={isPending}
                className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 text-sm font-semibold text-text-secondary transition hover:bg-surface hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:opacity-60"
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
              className="mt-3 rounded-control border border-danger/20 bg-surface-elevated px-3 py-2 text-sm leading-6 text-danger"
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
          className="inline-flex min-h-11 items-center rounded-control border border-border-control bg-surface-elevated px-3 py-2.5 text-sm font-medium text-text-secondary transition hover:border-danger/30 hover:bg-danger/5 hover:text-danger focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
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
