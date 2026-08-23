"use client";

import {
  useRef,
  useState,
  type ClipboardEvent,
  type KeyboardEvent,
} from "react";
import { useFormStatus } from "react-dom";

import {
  restoreTagInputValues,
  TAG_MAX_COUNT,
  validateTagInputValues,
} from "@/lib/tag-data";

type TagInputProps = {
  fieldError?: string;
  idPrefix: string;
  initialValues?: readonly string[];
};

export function TagInput({
  fieldError,
  idPrefix,
  initialValues = [],
}: TagInputProps) {
  const initialState = restoreTagInputValues(initialValues);
  const [tags, setTags] = useState(initialState.tags);
  const [draft, setDraft] = useState(initialState.draft);
  const [clientError, setClientError] = useState<string | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const isComposing = useRef(false);
  const { pending } = useFormStatus();
  const inputId = `${idPrefix}-tags`;
  const helpId = `${idPrefix}-tags-help`;
  const errorId = `${idPrefix}-tags-error`;
  const displayedError = clientError ?? fieldError;
  const isAtLimit = tags.length >= TAG_MAX_COUNT;

  function commitTags(rawValues: readonly string[]) {
    const result = validateTagInputValues([...tags, ...rawValues]);

    if (result.data === null) {
      setClientError(result.error);
      return;
    }

    const addedCount = result.data.length - tags.length;
    setTags(result.data);
    setDraft("");
    setClientError(null);

    if (addedCount > 0) {
      setAnnouncement(
        `${addedCount}件のタグを追加しました。現在${result.data.length}件です。`,
      );
    }
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (
      isComposing.current ||
      event.nativeEvent.isComposing ||
      !["Enter", ",", "，"].includes(event.key)
    ) {
      return;
    }

    event.preventDefault();
    const currentValue = event.currentTarget.value;

    if (currentValue !== "") {
      commitTags([currentValue]);
    }
  }

  function handlePaste(event: ClipboardEvent<HTMLInputElement>) {
    if (isComposing.current) {
      return;
    }

    const pastedValue = event.clipboardData.getData("text");

    if (!/[,，\r\n]/u.test(pastedValue)) {
      return;
    }

    event.preventDefault();
    const input = event.currentTarget;
    const currentValue = input.value;
    const selectionStart = input.selectionStart ?? currentValue.length;
    const selectionEnd = input.selectionEnd ?? selectionStart;
    const combinedValue =
      currentValue.slice(0, selectionStart) +
      pastedValue +
      currentValue.slice(selectionEnd);
    commitTags([combinedValue]);
  }

  function removeTag(tagToRemove: string) {
    setTags((currentTags) =>
      currentTags.filter((tag) => tag !== tagToRemove),
    );
    setClientError(null);
    setAnnouncement(`「${tagToRemove}」を削除しました。`);
  }

  return (
    <fieldset className="min-w-0" disabled={pending}>
      <legend className="text-sm font-medium text-text-secondary">
        タグ
        <span className="ml-2 text-xs font-normal text-text-muted">任意</span>
      </legend>

      {tags.map((tag) => (
        <input key={tag} name="tags" type="hidden" value={tag} />
      ))}
      <label className="sr-only" htmlFor={inputId}>
        タグを入力
      </label>

      <div className="mt-2 flex min-w-0 max-w-full flex-wrap gap-2 rounded-control border border-border-control bg-surface p-2 transition focus-within:border-focus focus-within:ring-2 focus-within:ring-brand-soft">
        {tags.map((tag) => (
          <span
            className="flex min-w-0 max-w-full items-center gap-1 rounded-full bg-brand-soft py-1 pl-3 pr-1 text-sm font-medium text-brand-primary-hover"
            key={tag}
          >
            <span className="min-w-0 break-words [overflow-wrap:anywhere]">
              #{tag}
            </span>
            <button
              aria-label={`「${tag}」を削除`}
              className="flex size-11 shrink-0 items-center justify-center rounded-full text-xl leading-none text-brand-primary-hover transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-focus disabled:cursor-wait disabled:text-control-disabled-text"
              disabled={pending}
              onClick={() => removeTag(tag)}
              type="button"
            >
              <span aria-hidden="true">×</span>
            </button>
          </span>
        ))}

        <input
          aria-describedby={
            displayedError ? `${helpId} ${errorId}` : helpId
          }
          aria-invalid={Boolean(displayedError)}
          className="min-h-11 min-w-32 flex-1 basis-40 bg-transparent px-2 py-2 text-base text-text-primary outline-none placeholder:text-text-muted disabled:cursor-not-allowed disabled:text-control-disabled-text"
          disabled={pending || isAtLimit}
          id={inputId}
          name="tags"
          onChange={(event) => {
            setDraft(event.target.value);
            setClientError(null);
          }}
          onCompositionEnd={() => {
            isComposing.current = false;
          }}
          onCompositionStart={() => {
            isComposing.current = true;
          }}
          onKeyDown={handleKeyDown}
          onPaste={handlePaste}
          placeholder={isAtLimit ? "5個まで追加済み" : "入力してEnterで追加"}
          type="text"
          value={draft}
        />
      </div>

      <div
        className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted"
        id={helpId}
      >
        <p>最大5個・1個30文字まで。カンマや改行でも追加できます。</p>
        <p aria-hidden="true" className="shrink-0">
          {tags.length} / {TAG_MAX_COUNT}
        </p>
      </div>

      {displayedError && (
        <p className="mt-2 text-sm text-danger" id={errorId} role="alert">
          {displayedError}
        </p>
      )}
      <p aria-live="polite" className="sr-only">
        {announcement}
      </p>
    </fieldset>
  );
}
