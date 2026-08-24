"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";

import {
  deletePost,
  type DeletePostActionState,
} from "@/app/(protected)/posts/actions";

function ConfirmDeleteButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="min-h-11 rounded-control bg-danger px-4 py-2.5 text-sm font-semibold text-white transition hover:opacity-90 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
      disabled={pending}
      type="submit"
    >
      {pending ? "削除中…" : "削除する"}
    </button>
  );
}

export function DeletePostButton({ postId }: { postId: string }) {
  const [isConfirming, setIsConfirming] = useState(false);
  const initialState: DeletePostActionState = { error: null };
  const [state, formAction] = useActionState(deletePost, initialState);
  const confirmationId = `delete-confirmation-${postId}`;

  return (
    <form
      action={formAction}
      className="mt-2 border-t border-border-subtle/70 pt-3"
    >
      <input name="postId" type="hidden" value={postId} />

      {state.error && (
        <p
          aria-live="polite"
          className="mb-3 rounded-control border border-danger/20 bg-danger/5 px-3 py-2 text-sm leading-6 text-danger"
          role="alert"
        >
          {state.error}
        </p>
      )}

      {isConfirming ? (
        <div
          className="rounded-control bg-surface-muted/70 p-4"
          id={confirmationId}
        >
          <p className="text-sm leading-6 text-text-secondary">
            この日記を削除しますか？削除後は一覧に表示されません。
          </p>
          <div className="mt-3 flex flex-wrap justify-end gap-2">
            <button
              className="min-h-11 rounded-control border border-border-subtle bg-surface-elevated px-4 py-2.5 text-sm font-semibold text-text-secondary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
              onClick={() => setIsConfirming(false)}
              type="button"
            >
              やめる
            </button>
            <ConfirmDeleteButton />
          </div>
        </div>
      ) : (
        <button
          aria-expanded={false}
          aria-controls={confirmationId}
          className="inline-flex min-h-11 items-center rounded-lg px-1 text-sm font-medium text-danger underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-danger"
          onClick={() => setIsConfirming(true)}
          type="button"
        >
          この日記を削除
        </button>
      )}
    </form>
  );
}
