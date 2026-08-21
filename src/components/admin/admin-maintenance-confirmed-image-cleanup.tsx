"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useId, useRef, useState } from "react";

import {
  cleanupConfirmedExchangeImages,
  type AdminExchangeImageCleanupActionState,
} from "@/app/(protected)/admin/maintenance/actions";

const initialState: AdminExchangeImageCleanupActionState = {
  outcome: "idle",
  revision: 0,
  selected: 0,
  processed: 0,
  reconciled: 0,
  unavailable: 0,
  failed: 0,
  unknown: 0,
  remainingDue: null,
};

function describeResult(state: AdminExchangeImageCleanupActionState) {
  const completedCount = state.processed + state.reconciled;
  const stoppedCount = state.unavailable + state.failed + state.unknown;
  const unattemptedCount = Math.max(
    0,
    state.selected - completedCount - stoppedCount,
  );

  if (state.outcome === "success") {
    return `選択した${state.selected}件のうち、物理削除${state.processed}件、状態照合による整理${state.reconciled}件が完了しました。`;
  }

  if (state.outcome === "empty") {
    return "実行時点で、期限を過ぎた取り外し済み画像はありませんでした。";
  }

  if (state.outcome === "changed") {
    return state.reconciled > 0
      ? `削除結果を直接確認できなかった対象を現在の状態と照合し、${state.reconciled}件を整理しました。安全のため、後続の${unattemptedCount}件は実行していません。最新の件数を確認してください。`
      : "メンテナンス対象が更新されています。最新の件数を確認してください。";
  }

  if (state.outcome === "partial") {
    return `選択した${state.selected}件のうち、物理削除${state.processed}件、状態照合による整理${state.reconciled}件が完了しました。現在処理できない対象が${state.unavailable + state.failed}件あったため停止し、後続の${unattemptedCount}件は実行していません。`;
  }

  if (state.outcome === "unknown") {
    return `選択した${state.selected}件のうち、${completedCount}件の処理を確認しました。結果を確定できない処理が${state.unknown}件あったため停止し、後続の${unattemptedCount}件は実行していません。繰り返し実行せず、最新の状況を確認してください。`;
  }

  if (state.outcome === "error") {
    return "取り外し済み画像のメンテナンスを実行できませんでした。最新の状況を確認して、もう一度お試しください。";
  }

  return null;
}

export function AdminMaintenanceConfirmedImageCleanup({
  batchSize,
  dueCount,
  oldestDueAt,
  oldestDueLabel,
}: {
  batchSize: number;
  dueCount: number | null;
  oldestDueAt: string | null;
  oldestDueLabel: string | null;
}) {
  const router = useRouter();
  const confirmationId = useId();
  const confirmationTitleId = `${confirmationId}-title`;
  const confirmationDescriptionId = `${confirmationId}-description`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const cancelRef = useRef<HTMLButtonElement>(null);
  const feedbackRef = useRef<HTMLDivElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [state, formAction, isPending] = useActionState(
    cleanupConfirmedExchangeImages,
    initialState,
  );
  const feedback = describeResult(state);
  const summaryAvailable = dueCount !== null;
  const hasDueImages = summaryAvailable && dueCount > 0;
  const mustReloadAfterUnknown = state.outcome === "unknown";

  useEffect(() => {
    if (isConfirming) {
      cancelRef.current?.focus();
    }
  }, [isConfirming]);

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }

    if (isPending || state.outcome === "idle") {
      return;
    }

    router.refresh();

    const frame = requestAnimationFrame(() => {
      setIsConfirming(false);
      requestAnimationFrame(() => feedbackRef.current?.focus());
    });

    return () => cancelAnimationFrame(frame);
  }, [isPending, router, state.outcome, state.revision]);

  function closeConfirmation() {
    setIsConfirming(false);
    requestAnimationFrame(() => triggerRef.current?.focus());
  }

  function openConfirmation() {
    if (
      isPending ||
      submissionInFlight.current ||
      !hasDueImages ||
      mustReloadAfterUnknown
    ) {
      return;
    }

    setIsConfirming(true);
  }

  function preventDuplicateSubmission(event: React.FormEvent<HTMLFormElement>) {
    if (isPending || submissionInFlight.current) {
      event.preventDefault();
      return;
    }

    submissionInFlight.current = true;
  }

  return (
    <section
      aria-labelledby="confirmed-image-maintenance-heading"
      className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
    >
      <p className="text-sm font-semibold text-orange-700">交換日記画像</p>
      <h2
        className="mt-1 break-words text-xl font-bold text-stone-800 [overflow-wrap:anywhere]"
        id="confirmed-image-maintenance-heading"
      >
        取り外し済み画像
      </h2>
      <p className="mt-3 text-sm leading-6 text-stone-600">
        交換日記から取り外され、保持期間を過ぎた画像を、現在の保護状態を再確認してStorageから物理削除します。
      </p>

      {summaryAvailable ? (
        <dl className="mt-5 grid min-w-0 gap-4 rounded-2xl bg-stone-50 p-4 sm:grid-cols-2">
          <div className="min-w-0">
            <dt className="text-xs font-semibold text-stone-500">期限到達件数</dt>
            <dd className="mt-1 break-words text-2xl font-bold text-stone-900 [overflow-wrap:anywhere]">
              {dueCount}件
            </dd>
          </div>
          <div className="min-w-0">
            <dt className="text-xs font-semibold text-stone-500">最も古い期限</dt>
            <dd className="mt-1 break-words text-sm font-semibold text-stone-800 [overflow-wrap:anywhere]">
              {oldestDueAt && oldestDueLabel ? (
                <time dateTime={oldestDueAt}>{oldestDueLabel}</time>
              ) : (
                "対象なし"
              )}
            </dd>
          </div>
          <div className="min-w-0 sm:col-span-2">
            <dt className="text-xs font-semibold text-stone-500">1回の最大処理件数</dt>
            <dd className="mt-1 text-sm font-semibold text-stone-800">
              {batchSize}件
            </dd>
          </div>
        </dl>
      ) : (
        <div
          className="mt-5 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm leading-6 text-red-700"
          role="alert"
        >
          現在メンテナンス状況を取得できません。削除操作は利用できません。
        </div>
      )}

      {summaryAvailable && dueCount === 0 && (
        <p className="mt-5 rounded-2xl bg-stone-50 p-4 text-sm leading-6 text-stone-600">
          現在、期限を過ぎた取り外し済み画像はありません。
        </p>
      )}

      {!isPending && feedback && (
        <div
          aria-atomic="true"
          aria-live={
            state.outcome === "success" || state.outcome === "empty"
              ? "polite"
              : "assertive"
          }
          className={
            state.outcome === "success" || state.outcome === "empty"
              ? "mt-5 min-w-0 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm leading-6 text-emerald-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
              : "mt-5 min-w-0 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm leading-6 text-red-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
          }
          key={state.revision}
          ref={feedbackRef}
          role={
            state.outcome === "success" || state.outcome === "empty"
              ? "status"
              : "alert"
          }
          tabIndex={-1}
        >
          <p className="break-words [overflow-wrap:anywhere]">{feedback}</p>
          {state.remainingDue !== null && (
            <p className="mt-2 font-semibold">
              現在の期限到達件数：{state.remainingDue}件
            </p>
          )}
          {mustReloadAfterUnknown && (
            <a
              className="mt-3 inline-flex min-h-11 w-full items-center justify-center rounded-full border border-red-300 bg-white px-4 py-2.5 text-center font-semibold text-red-800 transition hover:bg-red-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 sm:w-auto"
              href="/admin/maintenance"
            >
              最新の状況を確認
            </a>
          )}
        </div>
      )}

      {isConfirming ? (
        <div
          aria-describedby={confirmationDescriptionId}
          aria-labelledby={confirmationTitleId}
          className="mt-5 min-w-0 rounded-2xl border border-red-200 bg-red-50 p-4"
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
            取り外し済み画像を物理削除しますか？
          </h3>
          <p
            className="mt-2 break-words text-sm leading-6 text-stone-700 [overflow-wrap:anywhere]"
            id={confirmationDescriptionId}
          >
            交換日記から取り外され、保持期間を過ぎた画像を最大{batchSize}
            件処理します。現在の保護状態を再確認してからStorageから削除します。削除した画像は元に戻せません。
          </p>

          <form
            action={formAction}
            className="mt-4 grid min-w-0 gap-2 sm:grid-cols-2"
            onSubmit={preventDuplicateSubmission}
          >
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full bg-red-700 px-4 py-2.5 font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:bg-stone-400 [overflow-wrap:anywhere]"
              disabled={isPending}
              type="submit"
            >
              {isPending ? "処理中…" : "画像を物理削除する"}
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
        <button
          aria-controls={confirmationId}
          aria-disabled={isPending || !hasDueImages || mustReloadAfterUnknown}
          aria-expanded={isConfirming}
          className="mt-5 min-h-11 w-full min-w-0 whitespace-normal break-words rounded-full bg-red-700 px-5 py-3 font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-not-allowed disabled:bg-stone-400 [overflow-wrap:anywhere]"
          disabled={isPending || !hasDueImages || mustReloadAfterUnknown}
          onClick={openConfirmation}
          ref={triggerRef}
          type="button"
        >
          取り外し済み画像を削除
        </button>
      )}

      <p aria-atomic="true" aria-live="polite" className="sr-only" role="status">
        {isPending ? "取り外し済み画像のメンテナンスを実行しています" : ""}
      </p>
    </section>
  );
}
