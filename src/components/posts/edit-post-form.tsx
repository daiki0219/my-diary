"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";

import {
  updatePost,
  type UpdatePostActionState,
} from "@/app/(protected)/posts/actions";
import {
  POST_MOOD_OPTIONS,
  POST_VISIBILITY_OPTIONS,
  type EditablePost,
  type PostMood,
  type PostVisibility,
} from "@/lib/post-data";

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400 sm:w-auto sm:min-w-36"
      disabled={pending}
      type="submit"
    >
      {pending ? "保存中…" : "変更を保存"}
    </button>
  );
}

export function EditPostForm({ post }: { post: EditablePost }) {
  const [title, setTitle] = useState(post.title ?? "");
  const [body, setBody] = useState(post.body);
  const [mood, setMood] = useState<PostMood | "">(post.mood ?? "");
  const [visibility, setVisibility] = useState<PostVisibility>(
    post.visibility,
  );
  const initialState: UpdatePostActionState = {
    error: null,
    fieldErrors: {},
  };
  const [state, formAction] = useActionState(updatePost, initialState);

  return (
    <form action={formAction} className="space-y-6">
      <input name="postId" type="hidden" value={post.id} />

      {state.error && (
        <p
          aria-live="polite"
          className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          {state.error}
        </p>
      )}

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="edit-post-title"
        >
          タイトル
          <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
        </label>
        <input
          aria-describedby={
            state.fieldErrors.title
              ? "edit-post-title-help edit-post-title-error"
              : "edit-post-title-help"
          }
          aria-invalid={Boolean(state.fieldErrors.title)}
          className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          id="edit-post-title"
          maxLength={120}
          name="title"
          onChange={(event) => setTitle(event.target.value)}
          type="text"
          value={title}
        />
        <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
          <p id="edit-post-title-help">120文字以下で入力してください。</p>
          <p aria-hidden="true" className="shrink-0">
            {Array.from(title).length} / 120
          </p>
        </div>
        {state.fieldErrors.title && (
          <p
            className="mt-2 text-sm text-red-700"
            id="edit-post-title-error"
            role="alert"
          >
            {state.fieldErrors.title}
          </p>
        )}
      </div>

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="edit-post-body"
        >
          本文
        </label>
        <textarea
          aria-describedby={
            state.fieldErrors.body
              ? "edit-post-body-help edit-post-body-error"
              : "edit-post-body-help"
          }
          aria-invalid={Boolean(state.fieldErrors.body)}
          className="min-h-64 w-full resize-y rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base leading-7 outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          id="edit-post-body"
          maxLength={10000}
          name="body"
          onChange={(event) => setBody(event.target.value)}
          value={body}
        />
        <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
          <p id="edit-post-body-help">10,000文字以下で入力してください。</p>
          <p aria-hidden="true" className="shrink-0">
            {Array.from(body).length} / 10,000
          </p>
        </div>
        {state.fieldErrors.body && (
          <p
            className="mt-2 text-sm text-red-700"
            id="edit-post-body-error"
            role="alert"
          >
            {state.fieldErrors.body}
          </p>
        )}
      </div>

      <div className="grid gap-6 sm:grid-cols-2">
        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="edit-post-mood"
          >
            気分
          </label>
          <select
            aria-describedby={
              state.fieldErrors.mood ? "edit-post-mood-error" : undefined
            }
            aria-invalid={Boolean(state.fieldErrors.mood)}
            className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
            id="edit-post-mood"
            name="mood"
            onChange={(event) =>
              setMood(event.target.value as PostMood | "")
            }
            value={mood}
          >
            <option value="">選択しない</option>
            {POST_MOOD_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          {state.fieldErrors.mood && (
            <p
              className="mt-2 text-sm text-red-700"
              id="edit-post-mood-error"
              role="alert"
            >
              {state.fieldErrors.mood}
            </p>
          )}
        </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="edit-post-visibility"
          >
            公開範囲
          </label>
          <select
            aria-describedby={
              state.fieldErrors.visibility
                ? "edit-post-visibility-help edit-post-visibility-error"
                : "edit-post-visibility-help"
            }
            aria-invalid={Boolean(state.fieldErrors.visibility)}
            className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
            id="edit-post-visibility"
            name="visibility"
            onChange={(event) =>
              setVisibility(event.target.value as PostVisibility)
            }
            value={visibility}
          >
            {POST_VISIBILITY_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <p
            className="mt-2 text-xs leading-5 text-stone-500"
            id="edit-post-visibility-help"
          >
            変更後の公開範囲は、保存後すぐに反映されます。
          </p>
          {state.fieldErrors.visibility && (
            <p
              className="mt-2 text-sm text-red-700"
              id="edit-post-visibility-error"
              role="alert"
            >
              {state.fieldErrors.visibility}
            </p>
          )}
        </div>
      </div>

      <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <Link
          className="rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 sm:min-w-36"
          href={`/posts/${post.id}`}
        >
          キャンセル
        </Link>
        <SubmitButton />
      </div>
    </form>
  );
}
