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
  createPost,
  type CreatePostActionState,
} from "@/app/(protected)/posts/actions";
import { TagInput } from "@/components/posts/tag-input";
import {
  POST_MOOD_OPTIONS,
  POST_VISIBILITY_OPTIONS,
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

type SelectedPostImage = {
  file: File;
  id: string;
  previewUrl: string;
};

function imageErrorState(
  previousState: CreatePostActionState,
  error: string,
): CreatePostActionState {
  return {
    error: "画像を投稿できませんでした。",
    fieldErrors: { images: error },
    imageErrorRevision: (previousState.imageErrorRevision ?? 0) + 1,
    submittedTagValues: previousState.submittedTagValues,
    revision: previousState.revision,
  };
}

function locationErrorState(
  previousState: CreatePostActionState,
  error: string,
): CreatePostActionState {
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
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [locationName, setLocationName] = useState("");
  const [selectedImages, setSelectedImages] = useState<SelectedPostImage[]>(
    [],
  );
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
  const selectedImagesRef = useRef<SelectedPostImage[]>([]);
  const submissionInFlight = useRef(false);
  const initialState: CreatePostActionState = {
    error: null,
    fieldErrors: {},
    submittedTagValues: null,
    revision: 0,
  };

  const submitPost = useCallback(
    async (
      previousState: CreatePostActionState,
      formData: FormData,
    ): Promise<CreatePostActionState> => {
      if (submissionInFlight.current) {
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

      const images = selectedImagesRef.current;
      const validation = validatePostImageFiles(
        images.map((image) => image.file),
      );

      if (validation.error) {
        submissionInFlight.current = false;
        return imageErrorState(previousState, validation.error);
      }

      const postId = crypto.randomUUID();
      const uploadedPaths: string[] = [];

      try {
        const supabase = createClient();
        let userId: string | null = null;

        if (images.length > 0) {
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

        for (const image of images) {
          const storagePath = createPostImageStoragePath(
            userId as string,
            postId,
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
              ...uploadedPaths,
              storagePath,
            ]);

            return imageErrorState(
              previousState,
              cleanupSucceeded
                ? "画像をアップロードできませんでした。時間をおいてもう一度お試しください。"
                : "画像のアップロードと後処理に失敗しました。時間をおいてもう一度お試しください。",
            );
          }

          uploadedPaths.push(storagePath);
        }

        formData.set("postId", postId);
        formData.delete("imagePaths");
        uploadedPaths.forEach((path) => formData.append("imagePaths", path));

        try {
          const result = await createPost(previousState, formData);

          if (result.shouldCleanupImageUploads) {
            const cleanupSucceeded = await cleanupPostImageUploads(
              supabase,
              uploadedPaths,
            );

            return {
              ...result,
              error: cleanupSucceeded
                ? result.error
                : "投稿に失敗し、画像の後処理も完了できませんでした。時間をおいてもう一度お試しください。",
              shouldCleanupImageUploads: false,
            };
          }

          if (result.createdPostId) {
            router.replace("/profile/posts?status=created");
          }

          return result;
        } catch {
          return {
            error:
              "通信が途切れ、投稿結果を確認できませんでした。画像は削除していません。自分の日記一覧で投稿を確認してから、必要に応じてもう一度お試しください。",
            fieldErrors: {},
            submittedTagValues: previousState.submittedTagValues,
            revision: previousState.revision,
          };
        }
      } finally {
        submissionInFlight.current = false;
      }
    },
    [router],
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

  useEffect(() => {
    return () => {
      selectedImagesRef.current.forEach((image) => {
        URL.revokeObjectURL(image.previewUrl);
      });
    };
  }, []);

  function handleImageSelection(event: ChangeEvent<HTMLInputElement>) {
    const newFiles = Array.from(event.currentTarget.files ?? []);
    event.currentTarget.value = "";

    if (newFiles.length === 0) {
      return;
    }

    const combinedFiles = [
      ...selectedImagesRef.current.map((image) => image.file),
      ...newFiles,
    ];
    const validation = validatePostImageFiles(combinedFiles);

    if (validation.error) {
      setClientImageError(validation.error);
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
    setDismissedImageErrorKey(imageErrorKey);
    setImageAnnouncement(
      `${additions.length}枚の画像を追加しました。現在${nextImages.length}枚です。`,
    );
  }

  function removeImage(imageId: string) {
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
    setDismissedImageErrorKey(imageErrorKey);
    setImageAnnouncement(
      `「${imageToRemove.file.name}」を削除しました。現在${nextImages.length}枚です。`,
    );
  }

  return (
    <form action={formAction}>
      <fieldset className="min-w-0 space-y-6" disabled={isPending}>
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

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="post-location"
        >
          場所
          <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
        </label>
        <input
          aria-describedby={
            displayedLocationError
              ? "post-location-help post-location-error"
              : "post-location-help"
          }
          aria-invalid={Boolean(displayedLocationError)}
          className="w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100"
          id="post-location"
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
        <div className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500">
          <p id="post-location-help">
            任意。場所の名前を自由に入力できます。
          </p>
          <p aria-hidden="true" className="shrink-0">
            {getPostLocationNameCharacterCount(normalizedLocationName)} /{" "}
            {POST_LOCATION_NAME_MAX_LENGTH}
          </p>
        </div>
        {displayedLocationError && (
          <p
            className="mt-2 text-sm text-red-700"
            id="post-location-error"
            role="alert"
          >
            {displayedLocationError}
          </p>
        )}
      </div>

      <TagInput
        fieldError={state.fieldErrors.tags}
        idPrefix="post"
        initialValues={state.submittedTagValues ?? []}
        key={state.revision}
      />

      <div className="min-w-0">
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="post-images"
        >
          画像
          <span className="ml-2 text-xs font-normal text-stone-500">任意</span>
        </label>
        <input
          accept={POST_IMAGE_ALLOWED_MIME_TYPES.join(",")}
          aria-describedby={
            displayedImageError
              ? "post-images-help post-images-error"
              : "post-images-help"
          }
          aria-invalid={Boolean(displayedImageError)}
          className="block w-full min-w-0 rounded-2xl border border-stone-300 bg-white px-3 py-3 text-sm text-stone-700 file:mr-3 file:rounded-full file:border-0 file:bg-orange-50 file:px-4 file:py-2 file:font-semibold file:text-orange-800 hover:file:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-100"
          disabled={isPending || selectedImages.length >= POST_IMAGE_MAX_COUNT}
          id="post-images"
          multiple
          onChange={handleImageSelection}
          type="file"
        />
        <div
          className="mt-2 flex items-start justify-between gap-3 text-xs leading-5 text-stone-500"
          id="post-images-help"
        >
          <p>JPEG・PNG・WebP、1枚6MB以下。選択順で最大10枚まで。</p>
          <p className="shrink-0">
            <span className="sr-only">現在の選択数: </span>
            {selectedImages.length} / {POST_IMAGE_MAX_COUNT}
          </p>
        </div>

        {displayedImageError && (
          <p
            className="mt-2 text-sm text-red-700"
            id="post-images-error"
            role="alert"
          >
            {displayedImageError}
          </p>
        )}

        {selectedImages.length > 0 && (
          <ol
            aria-label="選択した画像（投稿順）"
            className="mt-4 grid min-w-0 grid-cols-2 gap-3 sm:grid-cols-3"
          >
            {selectedImages.map((image, index) => (
              <li
                className="min-w-0 overflow-hidden rounded-2xl border border-stone-200 bg-stone-50"
                key={image.id}
              >
                <div className="relative aspect-square overflow-hidden bg-stone-200">
                  <Image
                    alt=""
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
                    disabled={isPending}
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
          aria-disabled={isPending}
          className={`rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600 sm:min-w-36 ${isPending ? "pointer-events-none opacity-60" : "hover:bg-stone-50"}`}
          href="/profile/posts"
          tabIndex={isPending ? -1 : undefined}
        >
          キャンセル
        </Link>
        <SubmitButton />
      </div>
      </fieldset>
    </form>
  );
}
