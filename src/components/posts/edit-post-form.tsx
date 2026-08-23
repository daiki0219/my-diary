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

import {
  updatePost,
  type UpdatePostActionState,
} from "@/app/(protected)/posts/actions";
import { TagInput } from "@/components/posts/tag-input";
import { ActionLink, Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import {
  FormInput,
  FormSelect,
  FormTextarea,
} from "@/components/ui/form-controls";
import {
  POST_MOOD_OPTIONS,
  POST_VISIBILITY_OPTIONS,
  type EditablePost,
  type PostMood,
  type PostVisibility,
} from "@/lib/post-data";
import {
  createPostImageStoragePath,
  POST_IMAGE_ALLOWED_MIME_TYPES,
  POST_IMAGE_BUCKET,
  POST_IMAGE_MAX_COUNT,
  validatePostImageFiles,
} from "@/lib/post-image-data";
import {
  getPostLocationNameCharacterCount,
  getPostLocationNameError,
  normalizePostLocationName,
  POST_LOCATION_NAME_MAX_LENGTH,
} from "@/lib/post-location";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/client";

type ExistingEditImage = {
  id: string;
  kind: "existing";
};

type NewEditImage = {
  file: File;
  id: string;
  kind: "new";
  previewUrl: string;
};

type EditImage = ExistingEditImage | NewEditImage;

function imageErrorState(
  previousState: UpdatePostActionState,
  error: string,
): UpdatePostActionState {
  return {
    error: "画像を保存できませんでした。",
    fieldErrors: { images: error },
    imageErrorRevision: (previousState.imageErrorRevision ?? 0) + 1,
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision,
  };
}

function locationErrorState(
  previousState: UpdatePostActionState,
  error: string,
): UpdatePostActionState {
  return {
    error: "入力内容を確認してください。",
    fieldErrors: { location: error },
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision,
  };
}

async function cleanupPostImageUploads(
  supabase: ReturnType<typeof createClient>,
  imagePaths: readonly string[],
) {
  if (imagePaths.length === 0) {
    return true;
  }

  try {
    const { error } = await supabase.storage
      .from(POST_IMAGE_BUCKET)
      .remove([...imagePaths]);

    return !error;
  } catch {
    return false;
  }
}

export function EditPostForm({ post }: { post: EditablePost }) {
  const router = useRouter();
  const initialImages: EditImage[] = [...post.images]
    .sort((left, right) => left.sortOrder - right.sortOrder)
    .map((image) => ({ id: image.id, kind: "existing" }));
  const [title, setTitle] = useState(post.title ?? "");
  const [body, setBody] = useState(post.body);
  const [locationName, setLocationName] = useState(
    post.location_name ?? "",
  );
  const [mood, setMood] = useState<PostMood | "">(post.mood ?? "");
  const [visibility, setVisibility] = useState<PostVisibility>(
    post.visibility,
  );
  const [images, setImages] = useState<EditImage[]>(initialImages);
  const [clientImageError, setClientImageError] = useState<string | null>(
    null,
  );
  const [imageAnnouncement, setImageAnnouncement] = useState("");
  const [dismissedImageErrorKey, setDismissedImageErrorKey] = useState<
    string | null
  >(null);
  const [clientLocationError, setClientLocationError] = useState<
    string | null
  >(null);
  const [dismissedLocationErrorRevision, setDismissedLocationErrorRevision] =
    useState<number | null>(null);
  const imagesRef = useRef<EditImage[]>(initialImages);
  const submissionInFlight = useRef(false);
  const initialState: UpdatePostActionState = {
    error: null,
    fieldErrors: {},
    submittedTagValues: null,
    revision: 0,
  };

  const submitPost = useCallback(
    async (
      previousState: UpdatePostActionState,
      formData: FormData,
    ): Promise<UpdatePostActionState> => {
      if (submissionInFlight.current || previousState.outcomeUnknown) {
        return previousState;
      }

      submissionInFlight.current = true;
      const locationValue = formData.get("locationName");

      if (typeof locationValue !== "string") {
        submissionInFlight.current = false;
        return locationErrorState(
          previousState,
          "場所を正しく入力してください。",
        );
      }

      const locationError = getPostLocationNameError(locationValue);

      if (locationError) {
        submissionInFlight.current = false;
        return locationErrorState(previousState, locationError);
      }

      const currentImages = imagesRef.current;
      const newImages = currentImages.filter(
        (image): image is NewEditImage => image.kind === "new",
      );
      const validation = validatePostImageFiles(
        newImages.map((image) => image.file),
      );

      if (currentImages.length > POST_IMAGE_MAX_COUNT) {
        submissionInFlight.current = false;
        return imageErrorState(
          previousState,
          `画像は最大${POST_IMAGE_MAX_COUNT}枚まで選択できます。`,
        );
      }

      if (validation.error) {
        submissionInFlight.current = false;
        return imageErrorState(previousState, validation.error);
      }

      const uploadedPaths = new Map<string, string>();

      try {
        const supabase = createClient();
        let userId: string | null = null;

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
            );
          }

          userId = subject;
        }

        for (const image of newImages) {
          const storagePath = createPostImageStoragePath(
            userId as string,
            post.id,
            crypto.randomUUID(),
          );
          const uploadResult = await supabase.storage
            .from(POST_IMAGE_BUCKET)
            .upload(storagePath, image.file, {
              cacheControl: "3600",
              contentType: image.file.type,
              upsert: false,
            })
            .catch(() => null);

          if (!uploadResult || uploadResult.error) {
            const cleanupSucceeded = await cleanupPostImageUploads(supabase, [
              ...uploadedPaths.values(),
              storagePath,
            ]);

            return imageErrorState(
              previousState,
              cleanupSucceeded
                ? "画像をアップロードできませんでした。時間をおいてもう一度お試しください。"
                : "画像のアップロードと後処理に失敗しました。時間をおいてもう一度お試しください。",
            );
          }

          uploadedPaths.set(image.id, storagePath);
        }

        const manifest = currentImages.map((image) =>
          image.kind === "existing"
            ? { existingId: image.id }
            : { newPath: uploadedPaths.get(image.id) },
        );

        if (
          manifest.some(
            (item) => "newPath" in item && typeof item.newPath !== "string",
          )
        ) {
          const cleanupSucceeded = await cleanupPostImageUploads(
            supabase,
            [...uploadedPaths.values()],
          );

          return imageErrorState(
            previousState,
            cleanupSucceeded
              ? "投稿画像を確認できませんでした。もう一度お試しください。"
              : "投稿画像を確認できず、後処理も完了できませんでした。時間をおいてもう一度お試しください。",
          );
        }

        formData.set("imageManifest", JSON.stringify(manifest));

        try {
          const result = await updatePost(previousState, formData);

          if (result.shouldCleanupImageUploads) {
            const cleanupSucceeded = await cleanupPostImageUploads(
              supabase,
              [...uploadedPaths.values()],
            );

            return {
              ...result,
              error: cleanupSucceeded
                ? result.error
                : "投稿を更新できず、新しい画像の後処理も完了できませんでした。時間をおいてもう一度お試しください。",
              shouldCleanupImageUploads: false,
            };
          }

          if (result.updatedPostId) {
            const query = new URLSearchParams({ status: "updated" });

            if (result.cleanupWarning) {
              query.set("imageCleanup", "partial");
            }

            router.replace(`/posts/${result.updatedPostId}?${query}`);
          }

          return result;
        } catch {
          return {
            error:
              "通信が途切れ、更新結果を確認できませんでした。画像は削除していません。投稿の詳細を確認してから、必要に応じて画面を再読み込みしてください。",
            fieldErrors: {},
            outcomeUnknown: true,
            submittedTagValues: previousState.submittedTagValues,
            revision: previousState.revision,
          };
        }
      } finally {
        submissionInFlight.current = false;
      }
    },
    [post.id, router],
  );

  const [state, formAction, isPending] = useActionState(
    submitPost,
    initialState,
  );
  const imageErrorKey = `${state.revision}:${state.imageErrorRevision ?? 0}`;
  const displayedImageError =
    clientImageError ??
    (dismissedImageErrorKey === imageErrorKey
      ? undefined
      : state.fieldErrors.images);
  const displayedLocationError =
    clientLocationError ??
    (dismissedLocationErrorRevision === state.revision
      ? undefined
      : state.fieldErrors.location);
  const normalizedLocationName = normalizePostLocationName(locationName) ?? "";
  const formDisabled = isPending || Boolean(state.outcomeUnknown);

  useEffect(() => {
    return () => {
      imagesRef.current.forEach((image) => {
        if (image.kind === "new") {
          URL.revokeObjectURL(image.previewUrl);
        }
      });
    };
  }, []);

  function updateImages(nextImages: EditImage[]) {
    imagesRef.current = nextImages;
    setImages(nextImages);
    setClientImageError(null);
    setDismissedImageErrorKey(imageErrorKey);
  }

  function handleImageSelection(event: ChangeEvent<HTMLInputElement>) {
    const newFiles = Array.from(event.currentTarget.files ?? []);
    event.currentTarget.value = "";

    if (newFiles.length === 0) {
      return;
    }

    if (imagesRef.current.length + newFiles.length > POST_IMAGE_MAX_COUNT) {
      setClientImageError(
        `画像は最大${POST_IMAGE_MAX_COUNT}枚まで選択できます。`,
      );
      return;
    }

    const existingNewFiles = imagesRef.current.flatMap((image) =>
      image.kind === "new" ? [image.file] : [],
    );
    const validation = validatePostImageFiles([
      ...existingNewFiles,
      ...newFiles,
    ]);

    if (validation.error) {
      setClientImageError(validation.error);
      return;
    }

    const additions: NewEditImage[] = newFiles.map((file) => ({
      file,
      id: crypto.randomUUID(),
      kind: "new",
      previewUrl: URL.createObjectURL(file),
    }));
    const nextImages = [...imagesRef.current, ...additions];
    updateImages(nextImages);
    setImageAnnouncement(
      `${additions.length}枚の画像を追加しました。現在${nextImages.length}枚です。`,
    );
  }

  function removeImage(imageId: string) {
    const imageToRemove = imagesRef.current.find(
      (image) => image.id === imageId,
    );

    if (!imageToRemove) {
      return;
    }

    if (imageToRemove.kind === "new") {
      URL.revokeObjectURL(imageToRemove.previewUrl);
    }

    const nextImages = imagesRef.current.filter(
      (image) => image.id !== imageId,
    );
    updateImages(nextImages);
    setImageAnnouncement(
      `画像を削除対象にしました。現在${nextImages.length}枚です。`,
    );
  }

  function moveImage(index: number, direction: -1 | 1) {
    const destination = index + direction;

    if (destination < 0 || destination >= imagesRef.current.length) {
      return;
    }

    const nextImages = [...imagesRef.current];
    [nextImages[index], nextImages[destination]] = [
      nextImages[destination],
      nextImages[index],
    ];
    updateImages(nextImages);
    setImageAnnouncement(
      `画像を${destination + 1}番目へ移動しました。`,
    );
  }

  return (
    <form action={formAction}>
      <fieldset className="min-w-0 space-y-8" disabled={formDisabled}>
        {state.error && (
          <FeedbackPanel
            aria-live="polite"
            role="alert"
            variant="error"
          >
            {state.error}
          </FeedbackPanel>
        )}

        {state.outcomeUnknown && (
          <p className="text-sm leading-6 text-text-secondary">
            二重更新を防ぐためフォームを停止しました。投稿の詳細を確認するか、画面を再読み込みしてください。
          </p>
        )}

        <input name="postId" type="hidden" value={post.id} />

        <div className="space-y-6">
        <div>
          <label className="mb-2 block text-sm font-medium text-text-secondary" htmlFor="edit-post-title">
            タイトル
            <span className="ml-2 text-xs font-normal text-text-muted">任意</span>
          </label>
          <FormInput
            aria-describedby={state.fieldErrors.title ? "edit-post-title-help edit-post-title-error" : "edit-post-title-help"}
            aria-invalid={Boolean(state.fieldErrors.title)}
            id="edit-post-title"
            maxLength={120}
            name="title"
            onChange={(event) => setTitle(event.target.value)}
            type="text"
            value={title}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted">
            <p id="edit-post-title-help">120文字以下で入力してください。</p>
            <p aria-hidden="true" className="shrink-0">{Array.from(title).length} / 120</p>
          </div>
          {state.fieldErrors.title && <p className="mt-2 text-sm text-danger" id="edit-post-title-error" role="alert">{state.fieldErrors.title}</p>}
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium text-text-secondary" htmlFor="edit-post-body">
            本文
            <span className="ml-2 text-xs font-normal text-text-muted">必須</span>
          </label>
          <FormTextarea
            aria-describedby={state.fieldErrors.body ? "edit-post-body-help edit-post-body-error" : "edit-post-body-help"}
            aria-invalid={Boolean(state.fieldErrors.body)}
            className="min-h-72 resize-y leading-7 sm:min-h-80"
            id="edit-post-body"
            maxLength={10000}
            name="body"
            onChange={(event) => setBody(event.target.value)}
            required
            value={body}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted">
            <p id="edit-post-body-help">10,000文字以下で入力してください。</p>
            <p aria-hidden="true" className="shrink-0">{Array.from(body).length} / 10,000</p>
          </div>
          {state.fieldErrors.body && <p className="mt-2 text-sm text-danger" id="edit-post-body-error" role="alert">{state.fieldErrors.body}</p>}
        </div>
        </div>

        <section
          aria-labelledby="edit-post-details-heading"
          className="min-w-0 space-y-6 rounded-card bg-surface-muted/45 px-4 py-5 sm:px-5"
        >
          <div>
            <h2
              className="font-brand text-xl font-medium tracking-wide text-text-primary"
              id="edit-post-details-heading"
            >
              その日のこと
            </h2>
            <p className="mt-1 text-sm leading-6 text-text-muted">
              気分や場所、タグ、写真は必要なものだけ残せます。
            </p>
          </div>

          <div>
            <label className="mb-2 block text-sm font-medium text-text-secondary" htmlFor="edit-post-mood">気分</label>
            <FormSelect
              aria-describedby={state.fieldErrors.mood ? "edit-post-mood-error" : undefined}
              aria-invalid={Boolean(state.fieldErrors.mood)}
              id="edit-post-mood"
              name="mood"
              onChange={(event) => setMood(event.target.value as PostMood | "")}
              value={mood}
            >
              <option value="">選択しない</option>
              {POST_MOOD_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </FormSelect>
            {state.fieldErrors.mood && <p className="mt-2 text-sm text-danger" id="edit-post-mood-error" role="alert">{state.fieldErrors.mood}</p>}
          </div>

        <div>
          <label
            className="mb-2 block text-sm font-medium text-text-secondary"
            htmlFor="edit-post-location"
          >
            場所
            <span className="ml-2 text-xs font-normal text-text-muted">
              任意
            </span>
          </label>
          <FormInput
            aria-describedby={
              displayedLocationError
                ? "edit-post-location-help edit-post-location-error"
                : "edit-post-location-help"
            }
            aria-invalid={Boolean(displayedLocationError)}
            className="min-w-0"
            id="edit-post-location"
            name="locationName"
            onChange={(event) => {
              const nextLocationName = event.target.value;
              setLocationName(nextLocationName);
              setClientLocationError(
                getPostLocationNameError(nextLocationName),
              );
              setDismissedLocationErrorRevision(state.revision);
            }}
            placeholder="東京駅"
            type="text"
            value={locationName}
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted">
            <p id="edit-post-location-help">
              任意。場所の名前を100文字以下で入力できます。空欄で保存すると場所を削除します。
            </p>
            <p aria-hidden="true" className="shrink-0">
              {getPostLocationNameCharacterCount(normalizedLocationName)} /{" "}
              {POST_LOCATION_NAME_MAX_LENGTH}
            </p>
          </div>
          {displayedLocationError && (
            <p
              className="mt-2 text-sm text-danger"
              id="edit-post-location-error"
              role="alert"
            >
              {displayedLocationError}
            </p>
          )}
        </div>

        <TagInput
          fieldError={state.fieldErrors.tags}
          idPrefix="edit-post"
          initialValues={state.submittedTagValues ?? post.tags.map((tag) => tag.name)}
          key={state.revision}
        />

        <div className="min-w-0">
          <label className="mb-2 block text-sm font-medium text-text-secondary" htmlFor="edit-post-images">
            画像
            <span className="ml-2 text-xs font-normal text-text-muted">任意</span>
          </label>
          <input
            accept={POST_IMAGE_ALLOWED_MIME_TYPES.join(",")}
            aria-describedby={displayedImageError ? "edit-post-images-help edit-post-images-error" : "edit-post-images-help"}
            aria-invalid={Boolean(displayedImageError)}
            className="block w-full min-w-0 rounded-control border border-border-control bg-surface px-3 py-3 text-sm text-text-secondary file:mr-3 file:rounded-full file:border-0 file:bg-brand-soft file:px-4 file:py-2 file:font-semibold file:text-brand-primary-hover hover:file:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-wait disabled:bg-surface-muted"
            disabled={formDisabled || images.length >= POST_IMAGE_MAX_COUNT}
            id="edit-post-images"
            multiple
            onChange={handleImageSelection}
            type="file"
          />
          <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-text-muted" id="edit-post-images-help">
            <p>JPEG・PNG・WebP、1枚6MB以下。既存画像と合わせて最大10枚まで。</p>
            <p className="shrink-0"><span className="sr-only">現在の画像数: </span>{images.length} / {POST_IMAGE_MAX_COUNT}</p>
          </div>
          {displayedImageError && <p className="mt-2 text-sm text-danger" id="edit-post-images-error" role="alert">{displayedImageError}</p>}

          {images.length > 0 && (
            <ol aria-label="投稿画像（保存後の順序）" className="mt-4 grid min-w-0 grid-cols-2 gap-3 sm:grid-cols-3">
              {images.map((image, index) => (
                <li className="min-w-0 overflow-hidden rounded-control border border-border-subtle bg-surface-elevated" key={`${image.kind}:${image.id}`}>
                  <div className="relative aspect-square overflow-hidden bg-surface-muted">
                    <Image
                      alt=""
                      className="object-cover"
                      fill
                      loading={index === 0 ? "eager" : "lazy"}
                      sizes="(max-width: 639px) 50vw, 33vw"
                      src={image.kind === "existing" ? `/post-images/${image.id}` : image.previewUrl}
                      unoptimized
                    />
                    <span className="absolute left-2 top-2 rounded-full bg-stone-950/75 px-2 py-1 text-xs font-semibold text-white">{index + 1}</span>
                    <button
                      aria-label={`${image.kind === "existing" ? "既存" : "新規"}画像${index + 1}を削除`}
                      className="absolute right-1 top-1 flex size-11 items-center justify-center rounded-full bg-surface-elevated/95 text-xl leading-none text-text-primary shadow-sm transition hover:bg-surface-elevated focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:text-control-disabled-text"
                      onClick={() => removeImage(image.id)}
                      type="button"
                    >
                      <span aria-hidden="true">×</span>
                    </button>
                  </div>
                  <div className="space-y-2 px-2 py-2">
                    <p className="flex min-w-0 flex-wrap items-center gap-1.5 text-xs text-text-muted">
                      <span className="rounded-full bg-brand-soft px-2 py-1 font-medium text-brand-primary-hover">
                        {image.kind === "existing" ? "保存済み画像" : "追加する画像"}
                      </span>
                      <span>現在{index + 1}番目</span>
                    </p>
                    <div className="grid grid-cols-2 gap-2">
                      <button
                        aria-label={`${image.kind === "existing" ? "既存" : "新規"}画像${index + 1}を前へ移動`}
                        className="min-h-11 rounded-control border border-border-subtle bg-surface px-2 text-xs font-semibold text-text-secondary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-control-disabled-text"
                        disabled={index === 0}
                        onClick={() => moveImage(index, -1)}
                        type="button"
                      >
                        前へ
                      </button>
                      <button
                        aria-label={`${image.kind === "existing" ? "既存" : "新規"}画像${index + 1}を後ろへ移動`}
                        className="min-h-11 rounded-control border border-border-subtle bg-surface px-2 text-xs font-semibold text-text-secondary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus disabled:cursor-not-allowed disabled:bg-surface-muted disabled:text-control-disabled-text"
                        disabled={index === images.length - 1}
                        onClick={() => moveImage(index, 1)}
                        type="button"
                      >
                        後ろへ
                      </button>
                    </div>
                  </div>
                </li>
              ))}
            </ol>
          )}
          <p aria-live="polite" className="sr-only">{imageAnnouncement}</p>
        </div>
        </section>

        <section className="min-w-0 border-t border-border-subtle/70 pt-6">
            <label className="mb-2 block font-brand text-xl font-medium tracking-wide text-text-primary" htmlFor="edit-post-visibility">公開範囲</label>
            <FormSelect
              aria-describedby={state.fieldErrors.visibility ? "edit-post-visibility-help edit-post-visibility-error" : "edit-post-visibility-help"}
              aria-invalid={Boolean(state.fieldErrors.visibility)}
              id="edit-post-visibility"
              name="visibility"
              onChange={(event) => setVisibility(event.target.value as PostVisibility)}
              value={visibility}
            >
              {POST_VISIBILITY_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </FormSelect>
            <p className="mt-2 text-sm leading-6 text-text-muted" id="edit-post-visibility-help">誰に見える日記かを選びます。変更後の公開範囲は、保存後すぐに反映されます。</p>
            {state.fieldErrors.visibility && <p className="mt-2 text-sm text-danger" id="edit-post-visibility-error" role="alert">{state.fieldErrors.visibility}</p>}
        </section>

        <div className="flex flex-col gap-2 sm:items-end">
          <Button
            aria-disabled={formDisabled}
            className="w-full sm:w-auto sm:min-w-36"
            disabled={formDisabled}
            type="submit"
            variant="primary"
          >
            {isPending ? "保存中…" : state.outcomeUnknown ? "結果を確認してください" : "変更を保存"}
          </Button>
          <ActionLink className="w-full sm:w-auto sm:min-w-36" href={`/posts/${post.id}`} variant="quiet">キャンセル</ActionLink>
        </div>
      </fieldset>
    </form>
  );
}
