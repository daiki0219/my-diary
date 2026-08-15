"use client";

import { useRouter } from "next/navigation";
import {
  useActionState,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";

import {
  updateExchangeDiaryTitle,
  type ExchangeDiaryTitleActionState,
} from "@/app/(protected)/exchange/actions";
import { getUnicodeCodePointCount } from "@/lib/diary-entry-validation";

const TITLE_MAX_CODE_POINTS = 120;

export function ExchangeDiaryTitleForm({
  diaryId,
  initialTitle,
}: {
  diaryId: string;
  initialTitle: string | null;
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const errorRef = useRef<HTMLParagraphElement>(null);
  const submissionInFlight = useRef(false);
  const [title, setTitle] = useState(initialTitle ?? "");
  const initialState: ExchangeDiaryTitleActionState = {
    error: null,
    fieldError: null,
    completed: false,
    normalizedTitle: initialTitle ?? "",
    revision: 0,
  };
  const submitTitle = useCallback(
    async (
      previousState: ExchangeDiaryTitleActionState,
      formData: FormData,
    ) => {
      const nextState = await updateExchangeDiaryTitle(
        previousState,
        formData,
      );

      if (nextState.completed) {
        setTitle(nextState.normalizedTitle);
      }

      return nextState;
    },
    [],
  );
  const [state, formAction, isPending] = useActionState(
    submitTitle,
    initialState,
  );
  const titleLength = getUnicodeCodePointCount(title.trim());

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }
  }, [isPending, state.revision]);

  useEffect(() => {
    if (state.revision === 0) {
      return;
    }

    if (state.completed) {
      router.refresh();
      return;
    }

    if (state.fieldError) {
      inputRef.current?.focus();
      return;
    }

    if (state.error) {
      errorRef.current?.focus();
    }
  }, [router, state]);

  return (
    <form
      action={formAction}
      className="mt-5 rounded-2xl border border-orange-200 bg-white/80 p-4"
      onSubmit={(event) => {
        if (submissionInFlight.current) {
          event.preventDefault();
          return;
        }

        submissionInFlight.current = true;
      }}
    >
      <input name="diaryId" type="hidden" value={diaryId} />

      <fieldset disabled={isPending}>
        <label
          className="block text-sm font-semibold text-stone-800"
          htmlFor="exchange-diary-title"
        >
          交換日記のタイトル
          <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
        </label>
        <input
          aria-describedby={
            state.fieldError
              ? "exchange-diary-title-help exchange-diary-title-error"
              : "exchange-diary-title-help"
          }
          aria-invalid={Boolean(state.fieldError)}
          className="mt-2 w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 disabled:cursor-wait disabled:bg-stone-100"
          id="exchange-diary-title"
          name="title"
          onChange={(event) => setTitle(event.target.value)}
          ref={inputRef}
          type="text"
          value={title}
        />
        <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
          <p id="exchange-diary-title-help">
            空欄の場合は、相手の名前を使った表示名になります。
          </p>
          <p aria-hidden="true" className="shrink-0">
            {titleLength} / {TITLE_MAX_CODE_POINTS}
          </p>
        </div>

        {state.fieldError && (
          <p
            className="mt-2 text-sm text-red-700"
            id="exchange-diary-title-error"
            role="alert"
          >
            {state.fieldError}
          </p>
        )}

        {state.error && !state.fieldError && (
          <p
            className="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700 focus:outline-2 focus:outline-offset-2 focus:outline-red-600"
            key={state.revision}
            ref={errorRef}
            role="alert"
            tabIndex={-1}
          >
            {state.error}
          </p>
        )}

        {state.completed && (
          <p
            className="mt-3 text-sm font-medium text-emerald-700"
            key={state.revision}
            role="status"
          >
            タイトルを変更しました。
          </p>
        )}

        <button
          aria-disabled={isPending}
          className="mt-4 min-h-11 w-full rounded-full border border-orange-300 bg-orange-50 px-4 py-2.5 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:opacity-60 sm:w-auto"
          disabled={isPending}
          type="submit"
        >
          {isPending ? "変更中…" : "タイトルを変更"}
        </button>
        <p aria-live="polite" className="sr-only">
          {isPending ? "交換日記のタイトルを変更しています" : ""}
        </p>
      </fieldset>
    </form>
  );
}
