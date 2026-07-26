"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";

import {
  createComment,
  type CreateCommentActionState,
} from "@/app/(protected)/posts/actions";
import { COMMENT_MAX_LENGTH } from "@/lib/comment-data";

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400 sm:w-auto sm:min-w-32"
      disabled={pending}
      type="submit"
    >
      {pending ? "投稿中…" : "コメントする"}
    </button>
  );
}

export function CommentForm({ postId }: { postId: string }) {
  const [body, setBody] = useState("");
  const [state, setState] = useState<CreateCommentActionState>({
    error: null,
    fieldError: null,
    createdCommentId: null,
  });

  async function formAction(formData: FormData) {
    const nextState = await createComment(state, formData);
    setState(nextState);

    if (nextState.createdCommentId) {
      setBody("");
    }
  }

  return (
    <form
      action={formAction}
      className="mt-6 rounded-2xl border border-stone-200 bg-stone-50 p-4"
    >
      <input name="postId" type="hidden" value={postId} />

      <label
        className="mb-2 block text-sm font-semibold text-stone-700"
        htmlFor="comment-body"
      >
        コメントを書く
      </label>
      <textarea
        aria-describedby={
          state.fieldError
            ? "comment-body-help comment-body-error"
            : "comment-body-help"
        }
        aria-invalid={Boolean(state.fieldError)}
        className="min-h-28 w-full resize-y rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base leading-7 outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
        id="comment-body"
        maxLength={COMMENT_MAX_LENGTH}
        name="body"
        onChange={(event) => setBody(event.target.value)}
        required
        value={body}
      />
      <div className="mt-2 flex min-w-0 items-start justify-between gap-3 text-xs leading-5 text-stone-500">
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
        <p
          className="mt-2 text-sm text-red-700"
          id="comment-body-error"
          role="alert"
        >
          {state.fieldError}
        </p>
      )}

      {state.error && (
        <p
          aria-live="polite"
          className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700"
          role="alert"
        >
          {state.error}
        </p>
      )}

      {state.createdCommentId && (
        <p
          aria-live="polite"
          className="mt-3 text-sm text-green-800"
          role="status"
        >
          コメントを投稿しました。
        </p>
      )}

      <div className="mt-4 flex justify-end">
        <SubmitButton />
      </div>
    </form>
  );
}
