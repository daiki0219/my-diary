"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";

import {
  createPost,
  type CreatePostActionState,
} from "@/app/(protected)/posts/actions";
import { TagInput } from "@/components/posts/tag-input";
import {
  POST_MOOD_OPTIONS,
  POST_VISIBILITY_OPTIONS,
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
      {pending ? "投稿中…" : "投稿する"}
    </button>
  );
}

export function PostForm() {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const initialState: CreatePostActionState = {
    error: null,
    fieldErrors: {},
    submittedTagValues: null,
    revision: 0,
  };
  const [state, formAction] = useActionState(createPost, initialState);

  return (
    <form action={formAction} className="space-y-6">
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
          htmlFor="post-title"
        >
          タイトル
          <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
        </label>
        <input
          aria-describedby={
            state.fieldErrors.title
              ? "post-title-help post-title-error"
              : "post-title-help"
          }
          aria-invalid={Boolean(state.fieldErrors.title)}
          className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          id="post-title"
          maxLength={120}
          name="title"
          onChange={(event) => setTitle(event.target.value)}
          type="text"
          value={title}
        />
        <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
          <p id="post-title-help">120文字以下で入力してください。</p>
          <p aria-hidden="true" className="shrink-0">
            {Array.from(title).length} / 120
          </p>
        </div>
        {state.fieldErrors.title && (
          <p
            className="mt-2 text-sm text-red-700"
            id="post-title-error"
            role="alert"
          >
            {state.fieldErrors.title}
          </p>
        )}
      </div>

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="post-body"
        >
          本文
        </label>
        <textarea
          aria-describedby={
            state.fieldErrors.body
              ? "post-body-help post-body-error"
              : "post-body-help"
          }
          aria-invalid={Boolean(state.fieldErrors.body)}
          className="min-h-64 w-full resize-y rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base leading-7 outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          id="post-body"
          maxLength={10000}
          name="body"
          onChange={(event) => setBody(event.target.value)}
          required
          value={body}
        />
        <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
          <p id="post-body-help">10,000文字以下で入力してください。</p>
          <p aria-hidden="true" className="shrink-0">
            {Array.from(body).length} / 10,000
          </p>
        </div>
        {state.fieldErrors.body && (
          <p
            className="mt-2 text-sm text-red-700"
            id="post-body-error"
            role="alert"
          >
            {state.fieldErrors.body}
          </p>
        )}
      </div>

      <TagInput
        fieldError={state.fieldErrors.tags}
        idPrefix="post"
        initialValues={state.submittedTagValues ?? []}
        key={state.revision}
      />

      <div className="grid gap-6 sm:grid-cols-2">
        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="post-mood"
          >
            気分
          </label>
          <select
            aria-describedby={
              state.fieldErrors.mood ? "post-mood-error" : undefined
            }
            aria-invalid={Boolean(state.fieldErrors.mood)}
            className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
            defaultValue=""
            id="post-mood"
            name="mood"
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
              id="post-mood-error"
              role="alert"
            >
              {state.fieldErrors.mood}
            </p>
          )}
        </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="post-visibility"
          >
            公開範囲
          </label>
          <select
            aria-describedby={
              state.fieldErrors.visibility
                ? "post-visibility-error"
                : "post-visibility-help"
            }
            aria-invalid={Boolean(state.fieldErrors.visibility)}
            className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
            defaultValue="private"
            id="post-visibility"
            name="visibility"
          >
            {POST_VISIBILITY_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <p
            className="mt-2 text-xs leading-5 text-stone-500"
            id="post-visibility-help"
          >
            初期値は非公開です。
          </p>
          {state.fieldErrors.visibility && (
            <p
              className="mt-2 text-sm text-red-700"
              id="post-visibility-error"
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
          href="/profile/posts"
        >
          キャンセル
        </Link>
        <SubmitButton />
      </div>
    </form>
  );
}
