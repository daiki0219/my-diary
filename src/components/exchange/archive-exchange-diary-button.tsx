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
  const cancelRef = useRef<HTMLButtonElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [state, formAction, isPending] = useActionState(
    archiveExchangeDiary,
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
          className="rounded-control border border-danger/20 bg-danger/5 p-4"
          id={confirmationId}
          onKeyDown={(event) => {
            if (event.key === "Escape" && !isPending) {
              closeConfirmation();
            }
          }}
          role="alertdialog"
        >
          <h2
            className="text-base font-semibold leading-6 text-text-primary"
            id={titleId}
          >
            この交換日記を終了しますか？
          </h2>
          <div
            className="mt-2 space-y-2 text-sm leading-6 text-text-secondary"
            id={descriptionId}
          >
            <p>
              終了すると、この交換日記への新しい書き込みを終えます。新しい日記の作成や、これまでの日記・タイトル・通知設定の変更はできなくなります。
            </p>
            <p>
              これまでの日記は、過去の日記として引き続き読み返せます。自分が書いた日記は、終了後も削除できます。
            </p>
            <p className="font-semibold text-text-primary">
              この操作は元に戻せません。
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
              className="min-h-11 w-full rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 font-semibold text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:bg-surface-muted disabled:text-control-disabled-text"
              disabled={isPending}
              onClick={closeConfirmation}
              ref={cancelRef}
              type="button"
            >
              終了しない
            </button>
            <button
              aria-disabled={isPending}
              className="min-h-11 w-full rounded-control bg-danger px-4 py-2.5 font-semibold text-white transition hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
              disabled={isPending}
              type="submit"
            >
              {isPending ? "終了中…" : "交換日記を終了する"}
            </button>
          </form>

          <p aria-live="polite" className="sr-only">
            {isPending ? "交換日記を終了しています" : ""}
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
          className="-ml-3 inline-flex min-h-11 max-w-full items-center rounded-control px-3 py-2.5 text-left text-sm font-semibold leading-6 text-danger underline-offset-4 transition hover:bg-danger/5 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger"
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
