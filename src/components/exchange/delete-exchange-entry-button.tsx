"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, useId, useRef, useState } from "react";

import {
  deleteExchangeEntry,
  type ExchangeDiaryMutationActionState,
} from "@/app/(protected)/exchange/actions";

const initialState: ExchangeDiaryMutationActionState = {
  error: null,
  completed: false,
  revision: 0,
};

export function DeletedExchangeEntryStatus() {
  return (
    <p
      aria-atomic="true"
      aria-live="polite"
      className="mt-4 text-sm leading-6 text-stone-600"
      role="status"
    >
      この日記は削除されました
    </p>
  );
}

export function DeleteExchangeEntryButton({
  diaryId,
  entryId,
  accessibleName,
}: {
  diaryId: string;
  entryId: string;
  accessibleName: string;
}) {
  const router = useRouter();
  const confirmationId = useId();
  const titleId = `${confirmationId}-title`;
  const descriptionId = `${confirmationId}-description`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [state, formAction, isPending] = useActionState(
    deleteExchangeEntry,
    initialState,
  );

  useEffect(() => {
    if (isConfirming) {
      confirmRef.current?.focus();
    }
  }, [isConfirming]);

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }

    if (state.completed) {
      router.refresh();
    }
  }, [entryId, isPending, router, state]);

  function closeConfirmation() {
    setIsConfirming(false);
    requestAnimationFrame(() => triggerRef.current?.focus());
  }

  return (
    <div>
      {isConfirming ? (
        <div
          aria-describedby={descriptionId}
          aria-labelledby={titleId}
          className="min-w-0 rounded-2xl border border-red-200 bg-red-50 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="alertdialog"
        >
          <p className="text-sm font-bold leading-6 text-stone-800" id={titleId}>
            この日記を削除しますか？
          </p>
          <p className="mt-1 text-xs leading-5 text-stone-600" id={descriptionId}>
            削除すると元に戻せません。内容は「この日記は削除されました」という表示に置き換わります。
          </p>
          <form
            action={formAction}
            className="mt-3 grid gap-2 sm:grid-cols-2"
            onSubmit={(event) => {
              if (submissionInFlight.current) {
                event.preventDefault();
                return;
              }

              submissionInFlight.current = true;
            }}
          >
            <input name="diaryId" type="hidden" value={diaryId} />
            <input name="entryId" type="hidden" value={entryId} />
            <button
              aria-disabled={isPending}
              className="min-h-10 w-full rounded-full bg-red-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:bg-stone-400"
              disabled={isPending}
              ref={confirmRef}
              type="submit"
            >
              {isPending ? "削除中…" : "削除する"}
            </button>
            <button
              aria-disabled={isPending}
              className="min-h-10 w-full rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60"
              disabled={isPending}
              onClick={closeConfirmation}
              type="button"
            >
              削除しない
            </button>
          </form>
          <p aria-live="polite" className="sr-only">
            {isPending ? "日記を削除しています" : ""}
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
          className="inline-flex min-h-9 items-center rounded-full border border-red-300 bg-white px-3 py-1 text-xs font-semibold text-red-700 transition hover:bg-red-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
          onClick={() => setIsConfirming(true)}
          ref={triggerRef}
          type="button"
        >
          削除
        </button>
      )}
    </div>
  );
}
