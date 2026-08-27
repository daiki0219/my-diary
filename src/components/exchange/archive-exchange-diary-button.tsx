"use client";

import { useActionState, useEffect, useId, useRef, useState } from "react";

import {
  archiveExchangeDiary,
  type ExchangeDiaryMutationActionState,
} from "@/app/(protected)/exchange/actions";

const initialState: ExchangeDiaryMutationActionState = {
  error: null,
  completed: false,
  revision: 0,
};

export function ArchiveExchangeDiaryButton({ diaryId }: { diaryId: string }) {
  const confirmationId = useId();
  const titleId = `${confirmationId}-title`;
  const descriptionId = `${confirmationId}-description`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [state, formAction, isPending] = useActionState(
    archiveExchangeDiary,
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
  }, [isPending, state.revision]);

  function closeConfirmation() {
    setIsConfirming(false);
    requestAnimationFrame(() => triggerRef.current?.focus());
  }

  return (
    <div className="mt-4 min-w-0">
      {isConfirming ? (
        <div
          aria-describedby={descriptionId}
          aria-labelledby={titleId}
          className="rounded-2xl border border-red-200 bg-red-50 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="alertdialog"
        >
          <h2
            className="text-base font-bold leading-6 text-stone-800"
            id={titleId}
          >
            この交換日記を終了しますか？
          </h2>
          <div
            className="mt-2 space-y-2 text-sm leading-6 text-stone-700"
            id={descriptionId}
          >
            <p>
              終了後も過去の日記は読めますが、新しい日記の作成、既存の日記の編集、タイトル変更はできなくなります。
            </p>
            <p>
              終了した交換日記は再開できません。自分が書いた日記は、終了後も削除できます。
            </p>
          </div>

          <form
            action={formAction}
            className="mt-4 grid gap-2 sm:grid-cols-2"
            onSubmit={(event) => {
              if (submissionInFlight.current) {
                event.preventDefault();
                return;
              }

              submissionInFlight.current = true;
            }}
          >
            <input name="diaryId" type="hidden" value={diaryId} />
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full rounded-full bg-red-700 px-4 py-2.5 font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:bg-stone-400"
              disabled={isPending}
              ref={confirmRef}
              type="submit"
            >
              {isPending ? "終了中…" : "交換日記を終了する"}
            </button>
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full rounded-full border border-stone-300 bg-white px-4 py-2.5 font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 disabled:cursor-wait disabled:opacity-60"
              disabled={isPending}
              onClick={closeConfirmation}
              type="button"
            >
              終了しない
            </button>
          </form>

          <p aria-live="polite" className="sr-only">
            {isPending ? "交換日記を終了しています" : ""}
          </p>
          {state.error && (
            <p
              className="mt-3 rounded-xl border border-red-200 bg-white px-3 py-2 text-sm leading-6 text-red-700"
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
          className="min-h-11 w-full rounded-full border border-red-300 bg-white px-4 py-2.5 text-sm font-semibold text-red-700 transition hover:bg-red-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600"
          onClick={() => setIsConfirming(true)}
          ref={triggerRef}
          type="button"
        >
          交換日記を終了する
        </button>
      )}
    </div>
  );
}
