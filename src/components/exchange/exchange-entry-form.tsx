"use client";

import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  useActionState,
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
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
import {
  createExchangeEntryImageStoragePath,
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
  EXCHANGE_ENTRY_IMAGE_BUCKET,
  EXCHANGE_ENTRY_IMAGE_MAX_COUNT,
  validateExchangeEntryImageFiles,
} from "@/lib/exchange-entry-image-input";
import { POST_MOOD_OPTIONS } from "@/lib/post-data";
import {
  getPostLocationNameCharacterCount,
  normalizePostLocationName,
  POST_LOCATION_NAME_MAX_LENGTH,
} from "@/lib/post-location";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/client";

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

type SelectedExchangeEntryImage = {
  file: File;
  id: string;
  previewUrl: string;
};

function createImageErrorState(
  previousState: ExchangeEntryActionState,
  error: string,
): ExchangeEntryActionState {
  return {
    error: "画像を保存できませんでした。",
    fieldErrors: { images: error },
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision + 1,
    createOutcome: "idle",
  };
}

function unknownCreateOutcomeState(
  previousState: ExchangeEntryActionState,
): ExchangeEntryActionState {
  return {
    error:
      "通信が途切れ、保存結果を確認できませんでした。画像は削除していません。交換日記を再読み込みして保存結果を確認してください。",
    fieldErrors: {},
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision + 1,
    createOutcome: "unknown-outcome",
  };
}

async function cleanupExchangeEntryImageUploads(
  supabase: ReturnType<typeof createClient>,
  imagePaths: readonly string[],
) {
  if (imagePaths.length === 0) {
    return true;
  }

  try {
    const { error } = await supabase.storage
      .from(EXCHANGE_ENTRY_IMAGE_BUCKET)
      .remove([...imagePaths]);

    return !error;
  } catch {
    return false;
  }
}

function SubmitButton({
  mode,
  submissionBlocked,
}: {
  mode: "create" | "edit";
  submissionBlocked: boolean;
}) {
  const { pending } = useFormStatus();
  const disabled = pending || submissionBlocked;

  return (
    <button
      aria-disabled={disabled}
      className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400 sm:w-auto sm:min-w-36"
      disabled={disabled}
      type="submit"
    >
      {pending
        ? mode === "create"
          ? "保存中…"
          : "更新中…"
        : submissionBlocked
          ? "状態を確認してください"
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
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const generalErrorRef = useRef<HTMLParagraphElement>(null);
  const submissionInFlight = useRef(false);
  const submissionBlockedRef = useRef(false);
  const imageSelectionInFlight = useRef(false);
  const selectedImagesRef = useRef<SelectedExchangeEntryImage[]>([]);
  const [title, setTitle] = useState(entry?.title ?? "");
  const [body, setBody] = useState(entry?.body ?? "");
  const [mood, setMood] = useState(entry?.mood ?? "");
  const [locationName, setLocationName] = useState(
    entry?.locationName ?? "",
  );
  const [selectedImages, setSelectedImages] = useState<
    SelectedExchangeEntryImage[]
  >([]);
  const [clientImageError, setClientImageError] = useState<string | null>(
    null,
  );
  const [dismissedImageErrorRevision, setDismissedImageErrorRevision] =
    useState<number | null>(null);
  const [imageAnnouncement, setImageAnnouncement] = useState("");
  const [isValidatingImages, setIsValidatingImages] = useState(false);
  const [submissionBlocked, setSubmissionBlocked] = useState(false);
  const initialState: ExchangeEntryActionState = {
    error: null,
    fieldErrors: {},
    submittedTagValues: entry?.tags.map((tag) => tag.name) ?? [],
    revision: 0,
    createOutcome: mode === "create" ? "idle" : undefined,
  };
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
          createOutcome: mode === "create" ? "idle" : undefined,
        };
      }

      if (mode === "edit") {
        return updateExchangeEntry(previousState, formData);
      }

      const images = selectedImagesRef.current;
      const imageValidation = await validateExchangeEntryImageFiles(
        images.map((image) => image.file),
      );

      if (imageValidation.error) {
        return createImageErrorState(previousState, imageValidation.error);
      }

      const entryId = crypto.randomUUID();
      const uploadedPaths: string[] = [];
      const supabase = createClient();

      try {
        let currentUserId: string | null = null;

        if (images.length > 0) {
          const claimsResult = await supabase.auth.getClaims().catch(() => null);
          const subject = claimsResult?.data?.claims?.sub;

          if (
            !claimsResult ||
            claimsResult.error ||
            typeof subject !== "string" ||
            !isUuid(subject)
          ) {
            return createImageErrorState(
              previousState,
              "ログイン状態を確認できませんでした。もう一度ログインしてください。",
            );
          }

          currentUserId = subject.toLowerCase();
        }

        for (const image of images) {
          const storagePath = createExchangeEntryImageStoragePath({
            ownerUserId: currentUserId as string,
            diaryId,
            entryId,
            imageId: crypto.randomUUID(),
          });
          const uploadResult = await supabase.storage
            .from(EXCHANGE_ENTRY_IMAGE_BUCKET)
            .upload(storagePath, image.file, {
              cacheControl: "3600",
              contentType: image.file.type,
              upsert: false,
            })
            .catch(() => null);

          if (!uploadResult || uploadResult.error) {
            const cleanupSucceeded = await cleanupExchangeEntryImageUploads(
              supabase,
              uploadedPaths,
            );

            return createImageErrorState(
              previousState,
              cleanupSucceeded
                ? "画像をアップロードできませんでした。時間をおいてもう一度お試しください。"
                : "画像のアップロードと後処理を完了できませんでした。時間をおいてもう一度お試しください。",
            );
          }

          uploadedPaths.push(storagePath);
        }

        formData.set("entryId", entryId);
        formData.delete("imagePaths");
        uploadedPaths.forEach((path) => formData.append("imagePaths", path));

        let result: ExchangeEntryActionState;

        try {
          result = await createExchangeEntry(previousState, formData);
        } catch {
          submissionBlockedRef.current = true;
          setSubmissionBlocked(true);
          return unknownCreateOutcomeState(previousState);
        }

        if (result.createOutcome === "safe-to-cleanup") {
          const cleanupSucceeded = await cleanupExchangeEntryImageUploads(
            supabase,
            uploadedPaths,
          );

          return cleanupSucceeded
            ? result
            : {
                ...result,
                error:
                  "日記を保存できず、画像の後処理も完了できませんでした。時間をおいてもう一度お試しください。",
              };
        }

        if (
          result.createOutcome === "committed" &&
          result.createdEntryId === entryId
        ) {
          submissionBlockedRef.current = true;
          setSubmissionBlocked(true);
          router.replace(`/exchange/${diaryId}?view=latest`);
          return result;
        }

        submissionBlockedRef.current = true;
        setSubmissionBlocked(true);
        return result.createOutcome === "unknown-outcome"
          ? result
          : unknownCreateOutcomeState(previousState);
      } finally {
        submissionInFlight.current = false;
      }
    },
    [diaryId, mode, router],
  );
  const [state, formAction, isPending] = useActionState(
    submitEntry,
    initialState,
  );
  const normalizedTitle = title.trim();
  const normalizedBody = normalizeDiaryEntryBody(body);
  const normalizedLocationName = normalizePostLocationName(locationName) ?? "";
  const displayedImageError =
    clientImageError ??
    (dismissedImageErrorRevision === state.revision
      ? undefined
      : state.fieldErrors.images);
  const controlsDisabled =
    isPending || isValidatingImages || submissionBlocked;

  useEffect(() => {
    if (!isPending && !submissionBlockedRef.current) {
      submissionInFlight.current = false;
    }
  }, [isPending, state.revision]);

  useEffect(() => {
    return () => {
      selectedImagesRef.current.forEach((image) => {
        URL.revokeObjectURL(image.previewUrl);
      });
    };
  }, []);

  useEffect(() => {
    if (state.revision === 0 || !state.error) {
      return;
    }

    const firstInvalidField = (
      ["title", "body", "mood", "location", "tags", "images"] as const
    ).find((field) => Boolean(state.fieldErrors[field]));

    if (firstInvalidField) {
      const fieldId =
        firstInvalidField === "images"
          ? "exchange-entry-images"
          : FIELD_IDS[firstInvalidField];
      const field = formRef.current?.querySelector<HTMLElement>(
        `#${fieldId}`,
      );
      const fieldSection = formRef.current?.querySelector<HTMLElement>(
        firstInvalidField === "images"
          ? "#exchange-entry-images-section"
          : "#exchange-entry-tags-section",
      );

      if (field && !(field instanceof HTMLInputElement && field.disabled)) {
        field.focus();
      } else {
        fieldSection?.focus();
      }
      return;
    }

    generalErrorRef.current?.focus();
  }, [state.error, state.fieldErrors, state.revision]);

  async function handleImageSelection(event: ChangeEvent<HTMLInputElement>) {
    const newFiles = Array.from(event.currentTarget.files ?? []);
    event.currentTarget.value = "";

    if (
      mode !== "create" ||
      newFiles.length === 0 ||
      controlsDisabled ||
      imageSelectionInFlight.current
    ) {
      return;
    }

    imageSelectionInFlight.current = true;
    setIsValidatingImages(true);

    try {
      const combinedFiles = [
        ...selectedImagesRef.current.map((image) => image.file),
        ...newFiles,
      ];
      const validation = await validateExchangeEntryImageFiles(combinedFiles);

      if (validation.error) {
        setClientImageError(validation.error);
        requestAnimationFrame(() => {
          formRef.current
            ?.querySelector<HTMLInputElement>("#exchange-entry-images")
            ?.focus();
        });
        return;
      }

      const additions = newFiles.map((file) => ({
        file,
        id: crypto.randomUUID(),
        previewUrl: URL.createObjectURL(file),
      }));
      const nextImages = [...selectedImagesRef.current, ...additions];
      selectedImagesRef.current = nextImages;
      setSelectedImages(nextImages);
      setClientImageError(null);
      setDismissedImageErrorRevision(state.revision);
      setImageAnnouncement(
        `${additions.length}枚の画像を追加しました。現在${nextImages.length}枚です。`,
      );
    } finally {
      imageSelectionInFlight.current = false;
      setIsValidatingImages(false);
    }
  }

  function removeImage(imageId: string) {
    if (controlsDisabled) {
      return;
    }

    const imageToRemove = selectedImagesRef.current.find(
      (image) => image.id === imageId,
    );

    if (!imageToRemove) {
      return;
    }

    URL.revokeObjectURL(imageToRemove.previewUrl);
    const nextImages = selectedImagesRef.current.filter(
      (image) => image.id !== imageId,
    );
    selectedImagesRef.current = nextImages;
    setSelectedImages(nextImages);
    setClientImageError(null);
    setDismissedImageErrorRevision(state.revision);
    setImageAnnouncement(
      `「${imageToRemove.file.name}」を削除しました。現在${nextImages.length}枚です。`,
    );
  }

  return (
    <form
      action={formAction}
      onSubmit={(event) => {
        if (
          submissionBlockedRef.current ||
          imageSelectionInFlight.current ||
          submissionInFlight.current
        ) {
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

      <fieldset className="min-w-0 space-y-6" disabled={controlsDisabled}>
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

        {mode === "create" && (
          <div
            className="min-w-0 rounded-2xl focus:outline-2 focus:outline-offset-2 focus:outline-red-600"
            id="exchange-entry-images-section"
            tabIndex={-1}
          >
            <label
              className="mb-2 block text-sm font-medium text-stone-700"
              htmlFor="exchange-entry-images"
            >
              画像
              <span className="ml-2 text-xs font-normal text-stone-500">
                任意
              </span>
            </label>
            <input
              accept={EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES.join(",")}
              aria-describedby={
                displayedImageError
                  ? "exchange-entry-images-help exchange-entry-images-error"
                  : "exchange-entry-images-help"
              }
              aria-invalid={Boolean(displayedImageError)}
              className="block w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-3 py-3 text-sm text-stone-700 file:mr-3 file:rounded-full file:border-0 file:bg-orange-50 file:px-4 file:py-2 file:font-semibold file:text-orange-800 hover:file:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-100"
              disabled={
                controlsDisabled ||
                selectedImages.length >= EXCHANGE_ENTRY_IMAGE_MAX_COUNT
              }
              id="exchange-entry-images"
              multiple
              onChange={handleImageSelection}
              type="file"
            />
            <div
              className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500"
              id="exchange-entry-images-help"
            >
              <p>JPEG・PNG・WebP、1枚6MB以下。選択順で最大10枚まで。</p>
              <p className="shrink-0">
                <span className="sr-only">現在の選択数: </span>
                {selectedImages.length} / {EXCHANGE_ENTRY_IMAGE_MAX_COUNT}
              </p>
            </div>

            {displayedImageError && (
              <p
                className="mt-2 text-sm text-red-700"
                id="exchange-entry-images-error"
                role="alert"
              >
                {displayedImageError}
              </p>
            )}

            {selectedImages.length > 0 && (
              <ol
                aria-label="選択した交換日記の画像（保存順）"
                className="mt-4 grid min-w-0 grid-cols-2 gap-3 sm:grid-cols-3"
              >
                {selectedImages.map((image, index) => (
                  <li
                    className="min-w-0 overflow-hidden rounded-2xl border border-stone-200 bg-stone-50"
                    key={image.id}
                  >
                    <div className="relative aspect-square overflow-hidden bg-stone-200">
                      <Image
                        alt={`選択した画像${index + 1}「${image.file.name}」`}
                        className="object-cover"
                        fill
                        sizes="(max-width: 639px) 50vw, 33vw"
                        src={image.previewUrl}
                        unoptimized
                      />
                      <span className="absolute left-2 top-2 rounded-full bg-stone-950/75 px-2 py-1 text-xs font-semibold text-white">
                        {index + 1}
                      </span>
                      <button
                        aria-label={`画像${index + 1}「${image.file.name}」を選択から削除`}
                        className="absolute right-1 top-1 flex size-11 items-center justify-center rounded-full bg-white/95 text-xl leading-none text-stone-800 shadow-sm transition hover:bg-white focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:text-stone-400"
                        disabled={controlsDisabled}
                        onClick={() => removeImage(image.id)}
                        type="button"
                      >
                        <span aria-hidden="true">×</span>
                      </button>
                    </div>
                    <p className="min-w-0 break-words px-3 py-2 text-xs leading-5 text-stone-600 [overflow-wrap:anywhere]">
                      {image.file.name}
                    </p>
                  </li>
                ))}
              </ol>
            )}

            <p aria-live="polite" className="sr-only">
              {imageAnnouncement}
            </p>
          </div>
        )}

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
          <SubmitButton
            mode={mode}
            submissionBlocked={submissionBlocked || isValidatingImages}
          />
        </div>
        <p aria-live="polite" className="sr-only">
          {isValidatingImages
            ? "画像を確認しています"
            : isPending
            ? mode === "create"
              ? "日記を保存しています"
              : "日記を更新しています"
            : ""}
        </p>
      </fieldset>
    </form>
  );
}
