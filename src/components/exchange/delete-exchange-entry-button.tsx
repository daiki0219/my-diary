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
  const cancelRef = useRef<HTMLButtonElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [state, formAction, isPending] = useActionState(
    deleteExchangeEntry,
    initialState,
  );

  useEffect(() => {
    if (isConfirming) {
      cancelRef.current?.focus();
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
    <div className={isConfirming ? "min-w-0 basis-full" : "min-w-0"}>
      {isConfirming ? (
        <div
          aria-describedby={descriptionId}
          aria-labelledby={titleId}
          className="min-w-0 rounded-control border border-danger/20 bg-danger/5 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="alertdialog"
        >
          <h3
            className="text-base font-semibold leading-6 text-text-primary"
            id={titleId}
          >
            この日記を削除しますか？
          </h3>
          <div
            className="mt-2 space-y-2 text-sm leading-6 text-text-secondary"
            id={descriptionId}
          >
            <p>
              削除すると、交換日記では内容を読めなくなり、「この日記は削除されました」という表示に置き換わります。
            </p>
            <p className="font-semibold text-text-primary">
              この操作は元に戻せません。
            </p>
          </div>
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
              className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 text-sm font-semibold text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:bg-surface-muted disabled:text-control-disabled-text"
              disabled={isPending}
              onClick={closeConfirmation}
              ref={cancelRef}
              type="button"
            >
              削除しない
            </button>
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full rounded-control bg-danger px-4 py-2.5 text-sm font-semibold text-white transition hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
              disabled={isPending}
              type="submit"
            >
              {isPending ? "削除中…" : "この日記を削除する"}
            </button>
          </form>
          <p aria-live="polite" className="sr-only">
            {isPending ? "日記を削除しています" : ""}
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
          className="inline-flex min-h-11 items-center rounded-control px-3 py-2.5 text-sm font-medium text-danger underline-offset-4 transition hover:bg-danger/5 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger"
          onClick={() => setIsConfirming(true)}
          ref={triggerRef}
          type="button"
        >
          この日記を削除
        </button>
      )}
    </div>
  );
}
