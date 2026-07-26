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
      className="rounded-full bg-red-700 px-4 py-2 text-sm font-semibold text-white transition hover:bg-red-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700 disabled:cursor-wait disabled:bg-stone-400"
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
    <form action={formAction} className="mt-5 border-t border-stone-100 pt-4">
      <input name="postId" type="hidden" value={postId} />

      {state.error && (
        <p
          aria-live="polite"
          className="mb-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700"
          role="alert"
        >
          {state.error}
        </p>
      )}

      {isConfirming ? (
        <div
          className="rounded-2xl bg-stone-50 p-4"
          id={confirmationId}
        >
          <p className="text-sm leading-6 text-stone-700">
            この日記を削除しますか？削除後は一覧に表示されません。
          </p>
          <div className="mt-3 flex flex-wrap justify-end gap-2">
            <button
              className="rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
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
          className="rounded-lg text-sm font-semibold text-red-700 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-red-700"
          onClick={() => setIsConfirming(true)}
          type="button"
        >
          この日記を削除
        </button>
      )}
    </form>
  );
}
