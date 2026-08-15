"use client";

import Link from "next/link";
import {
  useActionState,
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";
import { useFormStatus } from "react-dom";

import {
  createExchangeEntry,
  updateExchangeEntry,
  type ExchangeEntryActionState,
} from "@/app/(protected)/exchange/actions";
import { TagInput } from "@/components/posts/tag-input";
import {
  DIARY_ENTRY_BODY_MAX_CODE_POINTS,
  DIARY_ENTRY_TITLE_MAX_CODE_POINTS,
  getUnicodeCodePointCount,
  normalizeDiaryEntryBody,
  validateDiaryEntryFormData,
  type DiaryEntryField,
} from "@/lib/diary-entry-validation";
import type { ExchangeActiveEntry } from "@/lib/exchange-data";
import { POST_MOOD_OPTIONS } from "@/lib/post-data";
import {
  getPostLocationNameCharacterCount,
  normalizePostLocationName,
  POST_LOCATION_NAME_MAX_LENGTH,
} from "@/lib/post-location";

type ExchangeEntryFormProps =
  | {
      mode: "create";
      diaryId: string;
      entry?: never;
    }
  | {
      mode: "edit";
      diaryId: string;
      entry: ExchangeActiveEntry;
    };

const FIELD_IDS: Record<DiaryEntryField, string> = {
  title: "exchange-entry-title",
  body: "exchange-entry-body",
  mood: "exchange-entry-mood",
  location: "exchange-entry-location",
  tags: "exchange-entry-tags",
};

function SubmitButton({ mode }: { mode: "create" | "edit" }) {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400 sm:w-auto sm:min-w-36"
      disabled={pending}
      type="submit"
    >
      {pending
        ? mode === "create"
          ? "保存中…"
          : "更新中…"
        : mode === "create"
          ? "日記を保存"
          : "変更を保存"}
    </button>
  );
}

export function ExchangeEntryForm({
  mode,
  diaryId,
  entry,
}: ExchangeEntryFormProps) {
  const formRef = useRef<HTMLFormElement>(null);
  const generalErrorRef = useRef<HTMLParagraphElement>(null);
  const submissionInFlight = useRef(false);
  const [title, setTitle] = useState(entry?.title ?? "");
  const [body, setBody] = useState(entry?.body ?? "");
  const [mood, setMood] = useState(entry?.mood ?? "");
  const [locationName, setLocationName] = useState(
    entry?.locationName ?? "",
  );
  const initialState: ExchangeEntryActionState = {
    error: null,
    fieldErrors: {},
    submittedTagValues: entry?.tags.map((tag) => tag.name) ?? [],
    revision: 0,
  };
  const serverAction =
    mode === "create" ? createExchangeEntry : updateExchangeEntry;
  const submitEntry = useCallback(
    async (
      previousState: ExchangeEntryActionState,
      formData: FormData,
    ): Promise<ExchangeEntryActionState> => {
      const validation = validateDiaryEntryFormData(formData);

      if (!validation.data) {
        return {
          error: "入力内容を確認してください。",
          fieldErrors: validation.fieldErrors,
          submittedTagValues: validation.submittedTagValues,
          revision: previousState.revision + 1,
        };
      }

      return serverAction(previousState, formData);
    },
    [serverAction],
  );
  const [state, formAction, isPending] = useActionState(
    submitEntry,
    initialState,
  );
  const normalizedTitle = title.trim();
  const normalizedBody = normalizeDiaryEntryBody(body);
  const normalizedLocationName = normalizePostLocationName(locationName) ?? "";

  useEffect(() => {
    if (!isPending) {
      submissionInFlight.current = false;
    }
  }, [isPending, state.revision]);

  useEffect(() => {
    if (state.revision === 0 || !state.error) {
      return;
    }

    const firstInvalidField = (
      ["title", "body", "mood", "location", "tags"] as const
    ).find((field) => Boolean(state.fieldErrors[field]));

    if (firstInvalidField) {
      const field = formRef.current?.querySelector<HTMLElement>(
        `#${FIELD_IDS[firstInvalidField]}`,
      );
      const tagSection = formRef.current?.querySelector<HTMLElement>(
        "#exchange-entry-tags-section",
      );

      if (field && !(field instanceof HTMLInputElement && field.disabled)) {
        field.focus();
      } else {
        tagSection?.focus();
      }
      return;
    }

    generalErrorRef.current?.focus();
  }, [state.error, state.fieldErrors, state.revision]);

  return (
    <form
      action={formAction}
      onSubmit={(event) => {
        if (submissionInFlight.current) {
          event.preventDefault();
          return;
        }

        submissionInFlight.current = true;
      }}
      ref={formRef}
    >
      <input name="diaryId" type="hidden" value={diaryId} />
      {mode === "edit" && (
        <input name="entryId" type="hidden" value={entry.entryId} />
      )}

      <fieldset className="min-w-0 space-y-6" disabled={isPending}>
        {state.error && (
          <p
            aria-live="polite"
            className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700 focus:outline-2 focus:outline-offset-2 focus:outline-red-600"
            ref={generalErrorRef}
            role="alert"
            tabIndex={-1}
          >
            {state.error}
          </p>
        )}

        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="exchange-entry-title"
          >
            タイトル
            <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
          </label>
          <input
            aria-describedby={
              state.fieldErrors.title
                ? "exchange-entry-title-help exchange-entry-title-error"
                : "exchange-entry-title-help"
            }
            aria-invalid={Boolean(state.fieldErrors.title)}
            className="w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 disabled:cursor-wait disabled:bg-stone-100"
            id="exchange-entry-title"
            name="title"
            onChange={(event) => setTitle(event.target.value)}
            type="text"
            value={title}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
            <p id="exchange-entry-title-help">空欄の場合はタイトルなしで保存します。</p>
            <p aria-hidden="true" className="shrink-0">
              {getUnicodeCodePointCount(normalizedTitle)} /{" "}
              {DIARY_ENTRY_TITLE_MAX_CODE_POINTS}
            </p>
          </div>
          {state.fieldErrors.title && (
            <p
              className="mt-2 text-sm text-red-700"
              id="exchange-entry-title-error"
              role="alert"
            >
              {state.fieldErrors.title}
            </p>
          )}
        </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="exchange-entry-body"
          >
            本文
          </label>
          <textarea
            aria-describedby={
              state.fieldErrors.body
                ? "exchange-entry-body-help exchange-entry-body-error"
                : "exchange-entry-body-help"
            }
            aria-invalid={Boolean(state.fieldErrors.body)}
            aria-required="true"
            className="min-h-64 w-full min-w-0 resize-y rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base leading-7 outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 disabled:cursor-wait disabled:bg-stone-100"
            id="exchange-entry-body"
            name="body"
            onChange={(event) => setBody(event.target.value)}
            value={body}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
            <p id="exchange-entry-body-help">必須。前後の空白を除いて10,000文字以下。</p>
            <p aria-hidden="true" className="shrink-0">
              {getUnicodeCodePointCount(normalizedBody)} /{" "}
              {DIARY_ENTRY_BODY_MAX_CODE_POINTS.toLocaleString("ja-JP")}
            </p>
          </div>
          {state.fieldErrors.body && (
            <p
              className="mt-2 text-sm text-red-700"
              id="exchange-entry-body-error"
              role="alert"
            >
              {state.fieldErrors.body}
            </p>
          )}
        </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="exchange-entry-mood"
          >
            気分
            <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
          </label>
          <select
            aria-describedby={
              state.fieldErrors.mood ? "exchange-entry-mood-error" : undefined
            }
            aria-invalid={Boolean(state.fieldErrors.mood)}
            className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 disabled:cursor-wait disabled:bg-stone-100"
            defaultValue={mood}
            id="exchange-entry-mood"
            key={state.revision}
            name="mood"
            onChange={(event) => {
              setMood(event.target.value);
            }}
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
              id="exchange-entry-mood-error"
              role="alert"
            >
              {state.fieldErrors.mood}
            </p>
          )}
        </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-stone-700"
            htmlFor="exchange-entry-location"
          >
            場所
            <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
          </label>
          <input
            aria-describedby={
              state.fieldErrors.location
                ? "exchange-entry-location-help exchange-entry-location-error"
                : "exchange-entry-location-help"
            }
            aria-invalid={Boolean(state.fieldErrors.location)}
            className="w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 disabled:cursor-wait disabled:bg-stone-100"
            id="exchange-entry-location"
            name="locationName"
            onChange={(event) => setLocationName(event.target.value)}
            placeholder="東京駅"
            type="text"
            value={locationName}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
            <p id="exchange-entry-location-help">場所の名前を自由に入力できます。</p>
            <p aria-hidden="true" className="shrink-0">
              {getPostLocationNameCharacterCount(normalizedLocationName)} /{" "}
              {POST_LOCATION_NAME_MAX_LENGTH}
            </p>
          </div>
          {state.fieldErrors.location && (
            <p
              className="mt-2 text-sm text-red-700"
              id="exchange-entry-location-error"
              role="alert"
            >
              {state.fieldErrors.location}
            </p>
          )}
        </div>

        <div
          className="rounded-2xl focus:outline-2 focus:outline-offset-2 focus:outline-red-600"
          id="exchange-entry-tags-section"
          tabIndex={-1}
        >
          <TagInput
            fieldError={state.fieldErrors.tags}
            idPrefix="exchange-entry"
            initialValues={state.submittedTagValues}
            key={state.revision}
          />
        </div>

        <div className="flex flex-col-reverse gap-3 pt-2 sm:flex-row sm:justify-end">
          <Link
            aria-disabled={isPending}
            className={`inline-flex min-h-12 w-full items-center justify-center rounded-full border border-stone-300 bg-white px-5 py-3 font-semibold text-stone-700 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 sm:w-auto ${
              isPending
                ? "pointer-events-none cursor-wait opacity-60"
                : "hover:bg-stone-50"
            }`}
            href={`/exchange/${diaryId}?view=latest`}
            tabIndex={isPending ? -1 : undefined}
          >
            キャンセル
          </Link>
          <SubmitButton mode={mode} />
        </div>
        <p aria-live="polite" className="sr-only">
          {isPending
            ? mode === "create"
              ? "日記を保存しています"
              : "日記を更新しています"
            : ""}
        </p>
      </fieldset>
    </form>
  );
}
