"use client";

import Image from "next/image";
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
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import {
  FormInput,
  FormSelect,
  FormTextarea,
} from "@/components/ui/form-controls";
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

type ExistingExchangeEntryImage = {
  id: string;
  kind: "existing";
};

type NewExchangeEntryImage = {
  file: File;
  id: string;
  kind: "new";
  previewUrl: string;
};

type ExchangeEntryImage =
  | ExistingExchangeEntryImage
  | NewExchangeEntryImage;

function imageErrorState(
  previousState: ExchangeEntryActionState,
  error: string,
  mode: "create" | "edit",
): ExchangeEntryActionState {
  return {
    error: "画像を保存できませんでした。",
    fieldErrors: { images: error },
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision + 1,
    createOutcome: mode === "create" ? "idle" : undefined,
    updateOutcome: mode === "edit" ? "idle" : undefined,
  };
}

function unknownMutationOutcomeState(
  previousState: ExchangeEntryActionState,
  mode: "create" | "edit",
): ExchangeEntryActionState {
  return {
    error:
      "通信が途切れ、保存結果を確認できませんでした。画像は削除していません。交換日記を再読み込みして保存結果を確認してください。",
    fieldErrors: {},
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision + 1,
    createOutcome: mode === "create" ? "unknown-outcome" : undefined,
    updateOutcome: mode === "edit" ? "unknown-outcome" : undefined,
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
  isValidatingImages,
  mode,
  submissionBlocked,
}: {
  isValidatingImages: boolean;
  mode: "create" | "edit";
  submissionBlocked: boolean;
}) {
  const { pending } = useFormStatus();
  const disabled = pending || isValidatingImages || submissionBlocked;

  return (
    <button
      aria-disabled={disabled}
      className="min-h-12 w-full rounded-control bg-brand-primary px-6 py-3 font-semibold text-white transition hover:bg-brand-primary-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text sm:w-auto sm:min-w-40"
      disabled={disabled}
      type="submit"
    >
      {pending
        ? mode === "create"
          ? "保存中…"
          : "更新中…"
        : isValidatingImages
          ? "画像を確認中…"
        : submissionBlocked
          ? "状態を確認してください"
        : mode === "create"
          ? "日記を書く"
          : "変更を保存"}
    </button>
  );
}

export function ExchangeEntryForm({
  mode,
  diaryId,
  entry,
}: ExchangeEntryFormProps) {
  const initialImages: ExchangeEntryImage[] =
    mode === "edit"
      ? [...entry.images]
          .sort((left, right) => left.sortOrder - right.sortOrder)
          .map((image) => ({ id: image.id, kind: "existing" }))
      : [];
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const generalErrorRef = useRef<HTMLDivElement>(null);
  const submissionInFlight = useRef(false);
  const submissionBlockedRef = useRef(false);
  const imageSelectionInFlight = useRef(false);
  const selectedImagesRef = useRef<ExchangeEntryImage[]>(initialImages);
  const [title, setTitle] = useState(entry?.title ?? "");
  const [body, setBody] = useState(entry?.body ?? "");
  const [mood, setMood] = useState(entry?.mood ?? "");
  const [locationName, setLocationName] = useState(
    entry?.locationName ?? "",
  );
  const [selectedImages, setSelectedImages] =
    useState<ExchangeEntryImage[]>(initialImages);
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
    updateOutcome: mode === "edit" ? "idle" : undefined,
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
          updateOutcome: mode === "edit" ? "idle" : undefined,
        };
      }

      const images = selectedImagesRef.current;
      const newImages = images.filter(
        (image): image is NewExchangeEntryImage => image.kind === "new",
      );

      if (images.length > EXCHANGE_ENTRY_IMAGE_MAX_COUNT) {
        return imageErrorState(
          previousState,
          `画像は最大${EXCHANGE_ENTRY_IMAGE_MAX_COUNT}枚まで選択できます。`,
          mode,
        );
      }

      const imageValidation = await validateExchangeEntryImageFiles(
        newImages.map((image) => image.file),
      );

      if (imageValidation.error) {
        return imageErrorState(previousState, imageValidation.error, mode);
      }

      const entryId = mode === "create" ? crypto.randomUUID() : entry.entryId;
      const uploadedPaths: string[] = [];
      const uploadedPathByClientId = new Map<string, string>();
      const supabase = createClient();

      try {
        let currentUserId: string | null = null;

        if (newImages.length > 0) {
          const claimsResult = await supabase.auth.getClaims().catch(() => null);
          const subject = claimsResult?.data?.claims?.sub;

          if (
            !claimsResult ||
            claimsResult.error ||
            typeof subject !== "string" ||
            !isUuid(subject)
          ) {
            return imageErrorState(
              previousState,
              "ログイン状態を確認できませんでした。もう一度ログインしてください。",
              mode,
            );
          }

          currentUserId = subject.toLowerCase();
        }

        for (const image of newImages) {
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

            return imageErrorState(
              previousState,
              cleanupSucceeded
                ? "画像をアップロードできませんでした。時間をおいてもう一度お試しください。"
                : "画像のアップロードと後処理を完了できませんでした。時間をおいてもう一度お試しください。",
              mode,
            );
          }

          uploadedPaths.push(storagePath);
          uploadedPathByClientId.set(image.id, storagePath);
        }

        if (mode === "create") {
          formData.set("entryId", entryId);
          formData.delete("imagePaths");
          uploadedPaths.forEach((path) => formData.append("imagePaths", path));
        } else {
          const imageManifest: Array<
            { existingId: string } | { newPath: string }
          > = [];

          for (const image of images) {
            if (image.kind === "existing") {
              imageManifest.push({ existingId: image.id });
              continue;
            }

            const uploadedPath = uploadedPathByClientId.get(image.id);

            if (!uploadedPath) {
              const cleanupSucceeded =
                await cleanupExchangeEntryImageUploads(
                  supabase,
                  uploadedPaths,
                );

              return imageErrorState(
                previousState,
                cleanupSucceeded
                  ? "画像をアップロードできませんでした。時間をおいてもう一度お試しください。"
                  : "画像のアップロードと後処理を完了できませんでした。時間をおいてもう一度お試しください。",
                mode,
              );
            }

            imageManifest.push({ newPath: uploadedPath });
          }

          formData.set("imageManifest", JSON.stringify(imageManifest));
        }

        let result: ExchangeEntryActionState;

        try {
          result =
            mode === "create"
              ? await createExchangeEntry(previousState, formData)
              : await updateExchangeEntry(previousState, formData);
        } catch {
          submissionBlockedRef.current = true;
          setSubmissionBlocked(true);
          return unknownMutationOutcomeState(previousState, mode);
        }

        const outcome =
          mode === "create" ? result.createOutcome : result.updateOutcome;

        if (outcome === "safe-to-cleanup") {
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

        const committedEntryId =
          mode === "create" ? result.createdEntryId : result.updatedEntryId;

        if (outcome === "committed" && committedEntryId === entryId) {
          submissionBlockedRef.current = true;
          setSubmissionBlocked(true);
          router.replace(`/exchange/${diaryId}?view=latest`);
          return result;
        }

        submissionBlockedRef.current = true;
        setSubmissionBlocked(true);
        return outcome === "unknown-outcome"
          ? result
          : unknownMutationOutcomeState(previousState, mode);
      } finally {
        submissionInFlight.current = false;
      }
    },
    [diaryId, entry, mode, router],
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
  const hasUnknownOutcome =
    state.createOutcome === "unknown-outcome" ||
    state.updateOutcome === "unknown-outcome";
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
        if (image.kind === "new") {
          URL.revokeObjectURL(image.previewUrl);
        }
      });
    };
  }, []);

  useEffect(() => {
    if (state.revision === 0 || !state.error) {
      return;
    }

    const firstInvalidField = (
      ["title", "body", "mood", "location", "images", "tags"] as const
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
      newFiles.length === 0 ||
      controlsDisabled ||
      imageSelectionInFlight.current
    ) {
      return;
    }

    imageSelectionInFlight.current = true;
    setIsValidatingImages(true);

    try {
      if (
        selectedImagesRef.current.length + newFiles.length >
        EXCHANGE_ENTRY_IMAGE_MAX_COUNT
      ) {
        setClientImageError(
          `画像は最大${EXCHANGE_ENTRY_IMAGE_MAX_COUNT}枚まで選択できます。`,
        );
        requestAnimationFrame(() => {
          formRef.current
            ?.querySelector<HTMLInputElement>("#exchange-entry-images")
            ?.focus();
        });
        return;
      }

      const existingNewFiles = selectedImagesRef.current.flatMap((image) =>
        image.kind === "new" ? [image.file] : [],
      );
      const combinedFiles = [
        ...existingNewFiles,
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
        kind: "new" as const,
        previewUrl: URL.createObjectURL(file),
      }));
      const nextImages = [...selectedImagesRef.current, ...additions];
      selectedImagesRef.current = nextImages;
      setSelectedImages(nextImages);
      setClientImageError(null);
      setDismissedImageErrorRevision(state.revision);
      setImageAnnouncement(
        `${additions.length}枚の写真を追加しました。現在${nextImages.length}枚です。`,
      );
    } finally {
      imageSelectionInFlight.current = false;
      setIsValidatingImages(false);
    }
  }

  function updateImages(nextImages: ExchangeEntryImage[]) {
    selectedImagesRef.current = nextImages;
    setSelectedImages(nextImages);
    setClientImageError(null);
    setDismissedImageErrorRevision(state.revision);
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

    if (imageToRemove.kind === "new") {
      URL.revokeObjectURL(imageToRemove.previewUrl);
    }
    const nextImages = selectedImagesRef.current.filter(
      (image) => image.id !== imageId,
    );
    updateImages(nextImages);
    setImageAnnouncement(
      imageToRemove.kind === "existing"
        ? `写真を一覧から外しました。保存すると日記から外れます。現在${nextImages.length}枚です。`
        : `選んだ写真を一覧から外しました。現在${nextImages.length}枚です。`,
    );
  }

  function moveImage(index: number, direction: -1 | 1) {
    if (controlsDisabled) {
      return;
    }

    const destination = index + direction;

    if (destination < 0 || destination >= selectedImagesRef.current.length) {
      return;
    }

    const nextImages = [...selectedImagesRef.current];
    [nextImages[index], nextImages[destination]] = [
      nextImages[destination],
      nextImages[index],
    ];
    updateImages(nextImages);
    setImageAnnouncement(`写真を${destination + 1}番目へ移動しました。`);
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

      <fieldset className="min-w-0 space-y-8" disabled={controlsDisabled}>
        {state.error && (
          <div
            className="rounded-control focus:outline-2 focus:outline-offset-2 focus:outline-focus"
            ref={generalErrorRef}
            tabIndex={-1}
          >
            <FeedbackPanel
              role="alert"
              title={
                hasUnknownOutcome
                  ? "保存結果を確認できませんでした"
                  : undefined
              }
              variant={hasUnknownOutcome ? "warning" : "error"}
            >
              {hasUnknownOutcome ? (
                <div className="space-y-3">
                  <p>
                    重複を避けるため、このままもう一度送信せず、まず交換日記を確認してください。
                  </p>
                  <p className="text-text-secondary">
                    写真を添えた場合も、保存結果が不明なまま削除はしていません。
                  </p>
                  <ActionLink
                    className="w-full bg-surface-elevated sm:w-auto"
                    href={`/exchange/${diaryId}?view=latest`}
                    variant="neutral"
                  >
                    交換日記を確認する
                  </ActionLink>
                </div>
              ) : (
                state.error
              )}
            </FeedbackPanel>
          </div>
        )}

        <section
          aria-labelledby="exchange-entry-writing-heading"
          className="min-w-0 space-y-6"
        >
          <div>
            <h2
              className="font-brand text-2xl font-medium tracking-wide text-text-primary"
              id="exchange-entry-writing-heading"
            >
              日記に残すこと
            </h2>
            <p className="mt-1 text-sm leading-6 text-text-muted">
              本文を中心に、今日のことをゆっくり綴ってください。
            </p>
          </div>

          <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="exchange-entry-title"
          >
            タイトル
            <span className="ml-2 text-xs font-normal text-text-muted">任意</span>
          </label>
          <FormInput
            aria-describedby={
              state.fieldErrors.title
                ? "exchange-entry-title-help exchange-entry-title-error"
                : "exchange-entry-title-help"
            }
            aria-invalid={Boolean(state.fieldErrors.title)}
            className="min-w-0 bg-surface-elevated"
            id="exchange-entry-title"
            name="title"
            onChange={(event) => setTitle(event.target.value)}
            type="text"
            value={title}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted">
            <p id="exchange-entry-title-help">空欄の場合はタイトルなしで保存します。</p>
            <p aria-hidden="true" className="shrink-0">
              {getUnicodeCodePointCount(normalizedTitle)} /{" "}
              {DIARY_ENTRY_TITLE_MAX_CODE_POINTS}
            </p>
          </div>
          {state.fieldErrors.title && (
            <p
              className="mt-2 text-sm text-danger"
              id="exchange-entry-title-error"
              role="alert"
            >
              {state.fieldErrors.title}
            </p>
          )}
        </div>

          <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="exchange-entry-body"
          >
            本文
            <span className="ml-2 text-xs font-normal text-text-muted">必須</span>
          </label>
          <FormTextarea
            aria-describedby={
              state.fieldErrors.body
                ? "exchange-entry-body-help exchange-entry-body-error"
                : "exchange-entry-body-help"
            }
            aria-invalid={Boolean(state.fieldErrors.body)}
            aria-required="true"
            className="min-h-72 min-w-0 resize-y bg-surface-elevated leading-8 sm:min-h-80"
            id="exchange-entry-body"
            name="body"
            onChange={(event) => setBody(event.target.value)}
            value={body}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted">
            <p id="exchange-entry-body-help">必須。前後の空白を除いて10,000文字以下。</p>
            <p aria-hidden="true" className="shrink-0">
              {getUnicodeCodePointCount(normalizedBody)} /{" "}
              {DIARY_ENTRY_BODY_MAX_CODE_POINTS.toLocaleString("ja-JP")}
            </p>
          </div>
          {state.fieldErrors.body && (
            <p
              className="mt-2 text-sm text-danger"
              id="exchange-entry-body-error"
              role="alert"
            >
              {state.fieldErrors.body}
            </p>
          )}
          </div>
        </section>

        <section
          aria-labelledby="exchange-entry-details-heading"
          className="min-w-0 space-y-6 rounded-card bg-surface-muted/45 px-4 py-5 sm:px-5"
        >
          <div>
            <h2
              className="font-brand text-xl font-medium tracking-wide text-text-primary"
              id="exchange-entry-details-heading"
            >
              その日のこと
            </h2>
            <p className="mt-1 text-sm leading-6 text-text-muted">
              気分や場所は、残したいときだけ添えられます。
            </p>
          </div>

          <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="exchange-entry-mood"
          >
            気分
            <span className="ml-2 text-xs font-normal text-text-muted">任意</span>
          </label>
          <FormSelect
            aria-describedby={
              state.fieldErrors.mood ? "exchange-entry-mood-error" : undefined
            }
            aria-invalid={Boolean(state.fieldErrors.mood)}
            className="bg-surface-elevated"
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
          </FormSelect>
          {state.fieldErrors.mood && (
            <p
              className="mt-2 text-sm text-danger"
              id="exchange-entry-mood-error"
              role="alert"
            >
              {state.fieldErrors.mood}
            </p>
          )}
        </div>

          <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="exchange-entry-location"
          >
            場所
            <span className="ml-2 text-xs font-normal text-text-muted">任意</span>
          </label>
          <FormInput
            aria-describedby={
              state.fieldErrors.location
                ? "exchange-entry-location-help exchange-entry-location-error"
                : "exchange-entry-location-help"
            }
            aria-invalid={Boolean(state.fieldErrors.location)}
            className="min-w-0 bg-surface-elevated"
            id="exchange-entry-location"
            name="locationName"
            onChange={(event) => setLocationName(event.target.value)}
            placeholder="東京駅"
            type="text"
            value={locationName}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted">
            <p id="exchange-entry-location-help">場所の名前を自由に入力できます。</p>
            <p aria-hidden="true" className="shrink-0">
              {getPostLocationNameCharacterCount(normalizedLocationName)} /{" "}
              {POST_LOCATION_NAME_MAX_LENGTH}
            </p>
          </div>
          {state.fieldErrors.location && (
            <p
              className="mt-2 text-sm text-danger"
              id="exchange-entry-location-error"
              role="alert"
            >
              {state.fieldErrors.location}
            </p>
          )}
          </div>
        </section>

        <section
          aria-labelledby="exchange-entry-images-heading"
          className="min-w-0 border-t border-border-subtle/70 pt-7"
        >
          <div>
            <h2
              className="font-brand text-xl font-medium tracking-wide text-text-primary"
              id="exchange-entry-images-heading"
            >
              写真を添える
            </h2>
            <p className="mt-1 text-sm leading-6 text-text-muted">
              保存後の日記に並ぶ順番で、写真を確認できます。
            </p>
          </div>

          <div
            className="mt-5 min-w-0 rounded-control focus:outline-2 focus:outline-offset-2 focus:outline-danger"
            id="exchange-entry-images-section"
            tabIndex={-1}
          >
            <label
              className="mb-2 block text-sm font-medium text-text-secondary"
              htmlFor="exchange-entry-images"
            >
              写真を選ぶ
              <span className="ml-2 text-xs font-normal text-text-muted">
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
              className="block w-full min-w-0 rounded-control border border-border-control bg-surface px-3 py-3 text-sm text-text-secondary file:mr-3 file:rounded-full file:border-0 file:bg-brand-soft file:px-4 file:py-2 file:font-semibold file:text-brand-primary-hover hover:file:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:bg-surface-muted"
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
              className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted"
              id="exchange-entry-images-help"
            >
              <p>
                {mode === "edit"
                  ? "JPEG・PNG・WebP、1枚6MB以下。現在の写真と合わせて最大10枚まで。取り外しや順番の変更は保存時に反映されます。"
                  : "JPEG・PNG・WebP、1枚6MB以下。選択順で最大10枚まで。選んだ写真は送信前に取り外せます。"}
              </p>
              <p className="shrink-0">
                <span className="sr-only">現在の写真数: </span>
                {selectedImages.length} / {EXCHANGE_ENTRY_IMAGE_MAX_COUNT}
              </p>
            </div>

            {displayedImageError && (
              <p
                className="mt-2 text-sm text-danger"
                id="exchange-entry-images-error"
                role="alert"
              >
                {displayedImageError}
              </p>
            )}

            {selectedImages.length > 0 && (
              <ol
                aria-label="交換日記の写真（保存後の順序）"
                className="mt-4 grid min-w-0 grid-cols-2 gap-3 sm:grid-cols-3"
              >
                {selectedImages.map((image, index) => (
                  <li
                    className="min-w-0 overflow-hidden rounded-control border border-border-subtle bg-surface-muted/45"
                    key={image.id}
                  >
                    <div className="relative aspect-square overflow-hidden bg-surface-muted">
                      <Image
                        alt=""
                        className="object-cover"
                        fill
                        loading="eager"
                        sizes="(max-width: 639px) 50vw, 33vw"
                        src={
                          image.kind === "existing"
                            ? `/exchange-entry-images/${image.id}`
                            : image.previewUrl
                        }
                        unoptimized
                      />
                      <span className="absolute left-2 top-2 rounded-full bg-stone-950/75 px-2 py-1 text-xs font-semibold text-white">
                        {index + 1}
                      </span>
                      <button
                        aria-label={`${index + 1}番目の写真を一覧から外す`}
                        className="absolute right-1 top-1 flex size-11 items-center justify-center rounded-full bg-surface-elevated/95 text-xl leading-none text-text-primary shadow-sm transition hover:bg-surface-elevated focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:text-control-disabled-text"
                        disabled={controlsDisabled}
                        onClick={() => removeImage(image.id)}
                        type="button"
                      >
                        <span aria-hidden="true">×</span>
                      </button>
                    </div>
                    <div className="space-y-2 px-2 py-2">
                      <p className="min-w-0 break-words text-xs font-medium leading-5 text-text-muted [overflow-wrap:anywhere]">
                        {image.kind === "existing"
                          ? `${index + 1}番目の写真`
                          : `${index + 1}番目「${image.file.name}」`}
                      </p>
                      {mode === "edit" && (
                        <div className="grid grid-cols-2 gap-2">
                          <button
                            aria-label={`${index + 1}番目の写真を前へ移動`}
                            className="min-h-11 rounded-control border border-border-subtle bg-surface px-2 text-xs font-semibold text-text-secondary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-control-disabled-text"
                            disabled={controlsDisabled || index === 0}
                            onClick={() => moveImage(index, -1)}
                            type="button"
                          >
                            前へ
                          </button>
                          <button
                            aria-label={`${index + 1}番目の写真を後ろへ移動`}
                            className="min-h-11 rounded-control border border-border-subtle bg-surface px-2 text-xs font-semibold text-text-secondary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-control-disabled-text"
                            disabled={
                              controlsDisabled ||
                              index === selectedImages.length - 1
                            }
                            onClick={() => moveImage(index, 1)}
                            type="button"
                          >
                            後ろへ
                          </button>
                        </div>
                      )}
                    </div>
                  </li>
                ))}
              </ol>
            )}

            <p aria-live="polite" className="sr-only">
              {imageAnnouncement}
            </p>
          </div>
        </section>

        <section
          aria-labelledby="exchange-entry-tags-heading"
          className="min-w-0 border-t border-border-subtle/70 pt-7"
        >
          <div>
            <h2
              className="font-brand text-xl font-medium tracking-wide text-text-primary"
              id="exchange-entry-tags-heading"
            >
              タグを添える
            </h2>
            <p className="mt-1 text-sm leading-6 text-text-muted">
              あとで思い出を見つけやすくしたいときに使えます。
            </p>
          </div>
          <div
            className="mt-5 rounded-control focus:outline-2 focus:outline-offset-2 focus:outline-danger"
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
        </section>

        <div className="flex flex-col gap-2 pt-1 sm:items-end">
          <SubmitButton
            isValidatingImages={isValidatingImages}
            mode={mode}
            submissionBlocked={submissionBlocked}
          />
          <ActionLink
            aria-disabled={isPending}
            className="w-full sm:w-auto sm:min-w-40"
            href={`/exchange/${diaryId}?view=latest`}
            tabIndex={isPending ? -1 : undefined}
            variant="quiet"
          >
            キャンセル
          </ActionLink>
        </div>
        <p aria-live="polite" className="sr-only">
          {isValidatingImages
            ? "写真を確認しています"
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
