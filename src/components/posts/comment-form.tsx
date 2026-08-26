"use client";

import { useActionState, useEffect, useId, useRef, useState } from "react";

import {
  createComment,
  type CreateCommentActionState,
} from "@/app/(protected)/posts/actions";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormTextarea } from "@/components/ui/form-controls";
import { COMMENT_MAX_LENGTH } from "@/lib/comment-data";

const initialState: CreateCommentActionState = {
  error: null,
  fieldError: null,
  createdCommentId: null,
};

export function CommentForm({ postId }: { postId: string }) {
  const dialogId = useId();
  const dialogTitleId = `${dialogId}-title`;
  const triggerId = `${dialogId}-trigger`;
  const dialogRef = useRef<HTMLDialogElement>(null);
  const errorRef = useRef<HTMLDivElement>(null);
  const submissionInFlight = useRef(false);
  const [body, setBody] = useState("");
  const [showSuccess, setShowSuccess] = useState(false);
  const [state, formAction, isPending] = useActionState(
    createComment,
    initialState,
  );

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }
  }, [isPending, state]);

  useEffect(() => {
    if (state.createdCommentId) {
      setBody("");
      setShowSuccess(true);
      dialogRef.current?.close();
      return;
    }

    if (state.fieldError) {
      requestAnimationFrame(() => {
        dialogRef.current
          ?.querySelector<HTMLTextAreaElement>("#comment-body")
          ?.focus();
      });
    } else if (state.error) {
      requestAnimationFrame(() => errorRef.current?.focus());
    }
  }, [state]);

  function openDialog() {
    const dialog = dialogRef.current;

    if (!dialog || dialog.open) {
      return;
    }

    setShowSuccess(false);
    dialog.showModal();
    requestAnimationFrame(() => {
      dialog.querySelector<HTMLTextAreaElement>("#comment-body")?.focus();
    });
  }

  function closeDialog() {
    if (!isPending && !submissionInFlight.current) {
      dialogRef.current?.close();
    }
  }

  return (
    <>
      <div
        className="mt-4 scroll-mt-16 lg:scroll-mt-28"
        id="comment-form"
      >
        <Button
          aria-controls={dialogId}
          aria-haspopup="dialog"
          className="w-full sm:w-auto"
          id={triggerId}
          onClick={openDialog}
          type="button"
          variant="secondary"
        >
          コメントを書く
        </Button>

        {showSuccess && (
          <FeedbackPanel className="mt-3" role="status" variant="success">
            コメントを投稿しました。
          </FeedbackPanel>
        )}
      </div>

      <dialog
        aria-labelledby={dialogTitleId}
        className="mx-auto mt-auto mb-0 max-h-[calc(100dvh-1rem)] w-[calc(100%-1rem)] max-w-none overflow-y-auto overscroll-contain rounded-t-card border border-border-subtle bg-surface-elevated p-0 text-text-primary shadow-surface backdrop:bg-text-primary/35 sm:m-auto sm:max-h-[calc(100dvh-3rem)] sm:w-[calc(100%-3rem)] sm:max-w-xl sm:rounded-card"
        id={dialogId}
        onCancel={(event) => {
          if (isPending || submissionInFlight.current) {
            event.preventDefault();
          }
        }}
        onClose={() => {
          requestAnimationFrame(() => {
            document.getElementById(triggerId)?.focus();
          });
        }}
        ref={dialogRef}
      >
        <div className="min-w-0 px-4 pt-5 pb-[calc(1.25rem+env(safe-area-inset-bottom))] sm:p-6">
          <h2
            className="text-xl font-semibold text-text-primary"
            id={dialogTitleId}
          >
            コメントを書く
          </h2>

          <form
            action={formAction}
            aria-busy={isPending}
            className="mt-5"
            onSubmit={(event) => {
              if (submissionInFlight.current) {
                event.preventDefault();
                return;
              }

              submissionInFlight.current = true;
              setShowSuccess(false);
            }}
          >
            <input name="postId" type="hidden" value={postId} />

            <label
              className="mb-2 block text-sm font-semibold text-text-primary"
              htmlFor="comment-body"
            >
              コメント本文
            </label>
            <FormTextarea
              aria-describedby={
                state.fieldError
                  ? "comment-body-help comment-body-error"
                  : "comment-body-help"
              }
              aria-invalid={Boolean(state.fieldError)}
              className="min-h-28 resize-y bg-surface leading-7"
              id="comment-body"
              maxLength={COMMENT_MAX_LENGTH}
              name="body"
              onChange={(event) => setBody(event.target.value)}
              required
              value={body}
            />
            <div className="mt-2 flex min-w-0 items-start justify-between gap-3 text-xs leading-5 text-text-muted">
              <p className="min-w-0" id="comment-body-help">
                {COMMENT_MAX_LENGTH.toLocaleString("ja-JP")}
                文字以下で入力してください。改行も使用できます。
              </p>
              <p aria-hidden="true" className="shrink-0">
                {Array.from(body).length} /{" "}
                {COMMENT_MAX_LENGTH.toLocaleString("ja-JP")}
              </p>
            </div>

            {state.fieldError && (
              <FeedbackPanel
                className="mt-3"
                id="comment-body-error"
                role="alert"
                variant="error"
              >
                {state.fieldError}
              </FeedbackPanel>
            )}

            {state.error && (
              <div ref={errorRef} tabIndex={-1}>
                <FeedbackPanel className="mt-3" role="alert" variant="error">
                  {state.error}
                </FeedbackPanel>
              </div>
            )}

            <div className="mt-5 grid gap-2 sm:flex sm:flex-wrap sm:justify-end">
              <Button
                aria-disabled={isPending}
                className="w-full sm:w-auto"
                disabled={isPending}
                onClick={closeDialog}
                type="button"
                variant="quiet"
              >
                キャンセル
              </Button>
              <Button
                aria-disabled={isPending}
                className="w-full sm:min-w-32 sm:w-auto"
                disabled={isPending}
                type="submit"
                variant="primary"
              >
                {isPending ? "投稿中…" : "コメントする"}
              </Button>
            </div>

            <p
              aria-atomic="true"
              aria-live="polite"
              className="sr-only"
              role="status"
            >
              {isPending ? "コメントを投稿しています" : ""}
            </p>
          </form>
        </div>
      </dialog>
    </>
  );
}
