"use client";

import { useActionState, useEffect, useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";

import {
  deleteComment,
  type DeleteCommentActionState,
} from "@/app/(protected)/posts/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";

const initialState: DeleteCommentActionState = { error: null };

export function DeleteCommentButton({
  commentId,
  postId,
}: {
  commentId: string;
  postId: string;
}) {
  const confirmationId = useId();
  const confirmationTitleId = `${confirmationId}-title`;
  const confirmationDescriptionId = `${confirmationId}-description`;
  const triggerRef = useRef<HTMLButtonElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const submissionInFlight = useRef(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const router = useRouter();
  const [state, formAction, isPending] = useActionState(
    deleteComment,
    initialState,
  );

  useEffect(() => {
    if (isConfirming) {
      confirmRef.current?.focus();
    }
  }, [isConfirming]);

  useEffect(() => {
    if (state.deletedCommentId) {
      router.refresh();
    }
  }, [router, state.deletedCommentId]);

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }
  }, [isPending, state]);

  function closeConfirmation() {
    setIsConfirming(false);
    requestAnimationFrame(() => triggerRef.current?.focus());
  }

  return (
    <form
      action={formAction}
      className={`min-w-0 ${
        isConfirming || state.error ? "basis-full pt-1" : ""
      }`}
      onSubmit={(event) => {
        if (submissionInFlight.current) {
          event.preventDefault();
          return;
        }

        submissionInFlight.current = true;
      }}
    >
      <input name="commentId" type="hidden" value={commentId} />
      <input name="postId" type="hidden" value={postId} />

      {state.error && (
        <FeedbackPanel className="mb-3" role="alert" variant="error">
          {state.error}
        </FeedbackPanel>
      )}

      {isConfirming ? (
        <div
          aria-describedby={confirmationDescriptionId}
          aria-labelledby={confirmationTitleId}
          className="rounded-control border border-danger/20 bg-danger/5 p-4"
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
            id={confirmationTitleId}
          >
            コメントを削除しますか？
          </h3>
          <p
            className="mt-1 text-sm leading-6 text-text-secondary"
            id={confirmationDescriptionId}
          >
            削除後は表示されません。
          </p>
          <div className="mt-3 flex flex-wrap justify-end gap-2">
            <button
              aria-disabled={isPending}
              className="inline-flex min-h-11 items-center justify-center rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 text-sm font-semibold text-text-secondary transition hover:bg-surface-muted hover:text-text-primary disabled:cursor-wait disabled:bg-surface-muted disabled:text-control-disabled-text"
              disabled={isPending}
              onClick={closeConfirmation}
              type="button"
            >
              やめる
            </button>
            <button
              aria-disabled={isPending}
              className="inline-flex min-h-11 items-center justify-center rounded-control bg-danger px-4 py-2.5 text-sm font-semibold text-white transition hover:opacity-90 disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
              disabled={isPending}
              ref={confirmRef}
              type="submit"
            >
              {isPending ? "削除中…" : "コメントを削除する"}
            </button>
          </div>
          <p aria-live="polite" className="sr-only">
            {isPending ? "コメントを削除しています" : ""}
          </p>
        </div>
      ) : (
        <button
          aria-controls={confirmationId}
          aria-expanded={isConfirming}
          className="inline-flex min-h-11 items-center rounded-control px-2 text-sm font-medium text-danger underline-offset-4 hover:bg-danger/5 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger"
          onClick={() => setIsConfirming(true)}
          ref={triggerRef}
          type="button"
        >
          このコメントを削除
        </button>
      )}
    </form>
  );
}
