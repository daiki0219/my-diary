"use server";

import { revalidatePath } from "next/cache";

import { COMMENT_MAX_LENGTH } from "@/lib/comment-data";
import {
  isPostMood,
  isPostVisibility,
} from "@/lib/post-data";
import {
  isPostImageStoragePathFor,
  POST_IMAGE_BUCKET,
  POST_IMAGE_MAX_COUNT,
} from "@/lib/post-image-data";
import { isUuid } from "@/lib/profile-data";
import {
  isReactionType,
  type ReactionType,
} from "@/lib/reaction-data";
import { createClient } from "@/lib/supabase/server";
import { validateTagInputValues } from "@/lib/tag-data";

export type CreatePostActionState = {
  error: string | null;
  createdPostId?: string;
  imageErrorRevision?: number;
  shouldCleanupImageUploads?: boolean;
  fieldErrors: {
    title?: string;
    body?: string;
    mood?: string;
    visibility?: string;
    tags?: string;
    images?: string;
  };
  submittedTagValues: string[] | null;
  revision: number;
};

export type UpdatePostActionState = CreatePostActionState & {
  cleanupWarning?: boolean;
  outcomeUnknown?: boolean;
  updatedPostId?: string;
};

type PostImageManifestItem =
  | { existingId: string }
  | { newPath: string };

type UpdatePostRpcResult = {
  postId: string;
  removedImagePaths: string[];
};

export type DeletePostActionState = {
  error: string | null;
};

export type ToggleReactionActionState = {
  error: string | null;
};

export type CreateCommentActionState = {
  error: string | null;
  fieldError: string | null;
  createdCommentId: string | null;
};

export type DeleteCommentActionState = {
  error: string | null;
};

function characterCount(value: string) {
  return Array.from(value).length;
}

function getValidatedTags(formData: FormData) {
  const entries = formData.getAll("tags");
  const submittedTagValues = entries.filter(
    (entry): entry is string => typeof entry === "string",
  );

  if (entries.length === 0 || submittedTagValues.length !== entries.length) {
    return {
      data: null,
      error: "タグの入力内容を確認してください。",
      submittedTagValues,
    };
  }

  const result = validateTagInputValues(submittedTagValues);
  return { ...result, submittedTagValues };
}

function inputErrorState(
  previousState: CreatePostActionState,
  fieldErrors: CreatePostActionState["fieldErrors"],
  submittedTagValues: string[],
): CreatePostActionState {
  return {
    error: "入力内容を確認してください。",
    fieldErrors,
    submittedTagValues,
    revision: previousState.revision + 1,
  };
}

function parsePostImageManifest(value: FormDataEntryValue | null) {
  if (typeof value !== "string") {
    return { data: null, error: "投稿画像を確認できませんでした。" };
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(value);
  } catch {
    return { data: null, error: "投稿画像を確認できませんでした。" };
  }

  if (!Array.isArray(parsed) || parsed.length > POST_IMAGE_MAX_COUNT) {
    return {
      data: null,
      error: `画像は最大${POST_IMAGE_MAX_COUNT}枚まで選択できます。`,
    };
  }

  const manifest: PostImageManifestItem[] = [];
  const existingIds = new Set<string>();
  const newPaths = new Set<string>();

  for (const item of parsed) {
    if (typeof item !== "object" || item === null) {
      return { data: null, error: "投稿画像を確認できませんでした。" };
    }

    const keys = Object.keys(item);

    if (keys.length !== 1) {
      return { data: null, error: "投稿画像を確認できませんでした。" };
    }

    if (
      keys[0] === "existingId" &&
      "existingId" in item &&
      typeof item.existingId === "string" &&
      isUuid(item.existingId) &&
      !existingIds.has(item.existingId)
    ) {
      existingIds.add(item.existingId);
      manifest.push({ existingId: item.existingId });
      continue;
    }

    if (
      keys[0] === "newPath" &&
      "newPath" in item &&
      typeof item.newPath === "string" &&
      !newPaths.has(item.newPath)
    ) {
      newPaths.add(item.newPath);
      manifest.push({ newPath: item.newPath });
      continue;
    }

    return { data: null, error: "投稿画像を確認できませんでした。" };
  }

  return { data: manifest, error: null };
}

function parseUpdatePostRpcResult(
  value: unknown,
  expectedPostId: string,
  expectedUserId: string,
): UpdatePostRpcResult | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }

  const keys = Object.keys(value);

  if (
    keys.length !== 2 ||
    !keys.includes("postId") ||
    !keys.includes("removedImagePaths") ||
    !("postId" in value) ||
    value.postId !== expectedPostId ||
    !("removedImagePaths" in value) ||
    !Array.isArray(value.removedImagePaths)
  ) {
    return null;
  }

  const removedImagePaths = value.removedImagePaths.filter(
    (path): path is string =>
      typeof path === "string" &&
      isPostImageStoragePathFor(path, expectedUserId, expectedPostId),
  );

  if (
    removedImagePaths.length !== value.removedImagePaths.length ||
    new Set(removedImagePaths).size !== removedImagePaths.length
  ) {
    return null;
  }

  return { postId: expectedPostId, removedImagePaths };
}

async function cleanupPostImageUploads(
  supabase: Awaited<ReturnType<typeof createClient>>,
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

async function createPostErrorState(
  supabase: Awaited<ReturnType<typeof createClient>>,
  imagePaths: readonly string[],
  previousState: CreatePostActionState,
  submittedTagValues: string[],
  options: {
    error: string;
    fieldErrors?: CreatePostActionState["fieldErrors"];
  },
): Promise<CreatePostActionState> {
  const cleanupSucceeded = await cleanupPostImageUploads(
    supabase,
    imagePaths,
  );

  return {
    error: cleanupSucceeded
      ? options.error
      : "投稿に失敗し、画像の後処理も完了できませんでした。時間をおいてもう一度お試しください。",
    fieldErrors: options.fieldErrors ?? {},
    submittedTagValues,
    revision: previousState.revision + 1,
  };
}

async function updatePostErrorState(
  supabase: Awaited<ReturnType<typeof createClient>>,
  newImagePaths: readonly string[],
  previousState: UpdatePostActionState,
  submittedTagValues: string[],
  options: {
    error: string;
    fieldErrors?: UpdatePostActionState["fieldErrors"];
  },
): Promise<UpdatePostActionState> {
  const cleanupSucceeded = await cleanupPostImageUploads(
    supabase,
    newImagePaths,
  );

  return {
    error: cleanupSucceeded
      ? options.error
      : "投稿を更新できず、新しい画像の後処理も完了できませんでした。時間をおいてもう一度お試しください。",
    fieldErrors: options.fieldErrors ?? {},
    submittedTagValues,
    revision: previousState.revision + 1,
  };
}

export async function createPost(
  previousState: CreatePostActionState,
  formData: FormData,
): Promise<CreatePostActionState> {
  const titleValue = formData.get("title");
  const bodyValue = formData.get("body");
  const moodValue = formData.get("mood");
  const visibilityValue = formData.get("visibility");
  const postIdValue = formData.get("postId");
  const imagePathEntries = formData.getAll("imagePaths");
  const imagePaths = imagePathEntries.filter(
    (entry): entry is string => typeof entry === "string",
  );
  const fieldErrors: CreatePostActionState["fieldErrors"] = {};
  const tagsResult = getValidatedTags(formData);

  if (titleValue !== null && typeof titleValue !== "string") {
    fieldErrors.title = "タイトルを正しく入力してください。";
  }

  if (typeof bodyValue !== "string") {
    fieldErrors.body = "本文を入力してください。";
  }

  if (moodValue !== null && typeof moodValue !== "string") {
    fieldErrors.mood = "気分を正しく選択してください。";
  }

  if (typeof visibilityValue !== "string") {
    fieldErrors.visibility = "公開範囲を選択してください。";
  }

  if (tagsResult.error) {
    fieldErrors.tags = tagsResult.error;
  }

  if (typeof postIdValue !== "string" || !isUuid(postIdValue)) {
    fieldErrors.images = "投稿画像を確認できませんでした。";
  }

  if (
    imagePathEntries.length !== imagePaths.length ||
    imagePaths.length > POST_IMAGE_MAX_COUNT
  ) {
    fieldErrors.images = `画像は最大${POST_IMAGE_MAX_COUNT}枚まで選択できます。`;
  }

  const normalizedTitle =
    typeof titleValue === "string" ? titleValue.trim() : "";
  const title = normalizedTitle || null;
  const body = typeof bodyValue === "string" ? bodyValue.trim() : "";
  const mood =
    typeof moodValue === "string" && moodValue !== ""
      ? moodValue
      : null;
  const visibility =
    typeof visibilityValue === "string" ? visibilityValue : "";
  const postId =
    typeof postIdValue === "string" && isUuid(postIdValue)
      ? postIdValue
      : null;

  if (title !== null && characterCount(title) > 120) {
    fieldErrors.title = "タイトルは120文字以下で入力してください。";
  }

  if (characterCount(body) < 1) {
    fieldErrors.body = "本文を入力してください。";
  } else if (characterCount(body) > 10000) {
    fieldErrors.body = "本文は10,000文字以下で入力してください。";
  }

  if (mood !== null && !isPostMood(mood)) {
    fieldErrors.mood = "選択された気分は使用できません。";
  }

  if (!isPostVisibility(visibility)) {
    fieldErrors.visibility = "選択された公開範囲は使用できません。";
  }

  const supabase = await createClient();
  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const userId = claimsResult?.data?.claims?.sub;

  if (!claimsResult || claimsResult.error || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
      fieldErrors: {},
      shouldCleanupImageUploads: imagePaths.length > 0,
      submittedTagValues: tagsResult.submittedTagValues,
      revision: previousState.revision + 1,
    };
  }

  const ownedImagePaths = postId
    ? imagePaths.filter((path) =>
        isPostImageStoragePathFor(path, userId, postId),
      )
    : [];

  if (ownedImagePaths.length !== imagePaths.length) {
    fieldErrors.images = "投稿画像を確認できませんでした。";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return createPostErrorState(
      supabase,
      ownedImagePaths,
      previousState,
      tagsResult.submittedTagValues,
      {
        error: "入力内容を確認してください。",
        fieldErrors,
      },
    );
  }

  const { data, error } = await supabase.rpc(
    "my_diary_create_post_with_images",
    {
      p_post_id: postId as string,
      p_title: title,
      p_body: body,
      p_mood: mood,
      p_visibility: visibility,
      p_tags: tagsResult.data,
      p_image_paths: imagePaths,
    },
  );

  if (error || typeof data !== "string" || !isUuid(data)) {
    if (error?.code === "22023") {
      return createPostErrorState(
        supabase,
        imagePaths,
        previousState,
        tagsResult.submittedTagValues,
        {
          error: "投稿内容を保存できませんでした。入力内容を確認してください。",
        },
      );
    }

    return createPostErrorState(
      supabase,
      imagePaths,
      previousState,
      tagsResult.submittedTagValues,
      {
        error:
          error?.code === "42501"
            ? "投稿を作成する権限がありません。アカウントの状態を確認してください。"
            : "投稿に失敗しました。時間をおいてもう一度お試しください。",
      },
    );
  }

  revalidatePath("/home");
  revalidatePath("/profile");
  revalidatePath("/profile/posts");
  revalidatePath(`/users/${userId}`);
  return {
    error: null,
    createdPostId: data,
    fieldErrors: {},
    submittedTagValues: tagsResult.submittedTagValues,
    revision: previousState.revision + 1,
  };
}

export async function updatePost(
  previousState: UpdatePostActionState,
  formData: FormData,
): Promise<UpdatePostActionState> {
  const postIdValue = formData.get("postId");
  const titleValue = formData.get("title");
  const bodyValue = formData.get("body");
  const moodValue = formData.get("mood");
  const visibilityValue = formData.get("visibility");
  const imageManifestResult = parsePostImageManifest(
    formData.get("imageManifest"),
  );
  const newImagePaths =
    imageManifestResult.data?.flatMap((item) =>
      "newPath" in item ? [item.newPath] : [],
    ) ?? [];
  const fieldErrors: UpdatePostActionState["fieldErrors"] = {};
  const tagsResult = getValidatedTags(formData);

  if (typeof postIdValue !== "string" || !isUuid(postIdValue)) {
    return {
      error: "更新する投稿を確認できませんでした。",
      fieldErrors,
      submittedTagValues: tagsResult.submittedTagValues,
      revision: previousState.revision + 1,
    };
  }

  if (titleValue !== null && typeof titleValue !== "string") {
    fieldErrors.title = "タイトルを正しく入力してください。";
  }

  if (typeof bodyValue !== "string") {
    fieldErrors.body = "本文を入力してください。";
  }

  if (moodValue !== null && typeof moodValue !== "string") {
    fieldErrors.mood = "気分を正しく選択してください。";
  }

  if (typeof visibilityValue !== "string") {
    fieldErrors.visibility = "公開範囲を選択してください。";
  }

  if (tagsResult.error) {
    fieldErrors.tags = tagsResult.error;
  }

  if (imageManifestResult.error) {
    fieldErrors.images = imageManifestResult.error;
  }

  if (Object.keys(fieldErrors).length > 0) {
    return {
      ...inputErrorState(
        previousState,
        fieldErrors,
        tagsResult.submittedTagValues,
      ),
      shouldCleanupImageUploads: newImagePaths.length > 0,
    };
  }

  const normalizedTitle =
    typeof titleValue === "string" ? titleValue.trim() : "";
  const title = normalizedTitle || null;
  const body = (bodyValue as string).trim();
  const mood =
    typeof moodValue === "string" && moodValue !== ""
      ? moodValue
      : null;
  const visibility = visibilityValue as string;

  if (title !== null && characterCount(title) > 120) {
    fieldErrors.title = "タイトルは120文字以下で入力してください。";
  }

  if (characterCount(body) < 1) {
    fieldErrors.body = "本文を入力してください。";
  } else if (characterCount(body) > 10000) {
    fieldErrors.body = "本文は10,000文字以下で入力してください。";
  }

  if (mood !== null && !isPostMood(mood)) {
    fieldErrors.mood = "選択された気分は使用できません。";
  }

  if (!isPostVisibility(visibility)) {
    fieldErrors.visibility = "選択された公開範囲は使用できません。";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return {
      ...inputErrorState(
        previousState,
        fieldErrors,
        tagsResult.submittedTagValues,
      ),
      shouldCleanupImageUploads: newImagePaths.length > 0,
    };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
      fieldErrors: {},
      shouldCleanupImageUploads: newImagePaths.length > 0,
      submittedTagValues: tagsResult.submittedTagValues,
      revision: previousState.revision + 1,
    };
  }

  const ownedNewImagePaths = newImagePaths.filter((path) =>
    isPostImageStoragePathFor(path, userId, postIdValue),
  );

  if (ownedNewImagePaths.length !== newImagePaths.length) {
    return {
      error: "入力内容を確認してください。",
      fieldErrors: { images: "投稿画像を確認できませんでした。" },
      shouldCleanupImageUploads: newImagePaths.length > 0,
      submittedTagValues: tagsResult.submittedTagValues,
      revision: previousState.revision + 1,
    };
  }

  let rpcResult: Awaited<ReturnType<typeof supabase.rpc>>;

  try {
    rpcResult = await supabase.rpc("my_diary_update_post_with_images", {
      p_post_id: postIdValue,
      p_title: title,
      p_body: body,
      p_mood: mood,
      p_visibility: visibility,
      p_tags: tagsResult.data,
      p_image_manifest: imageManifestResult.data,
    });
  } catch {
    return {
      error:
        "通信が途切れ、更新結果を確認できませんでした。画像は削除していません。投稿の詳細を確認してから、必要に応じてもう一度お試しください。",
      fieldErrors: {},
      outcomeUnknown: true,
      submittedTagValues: tagsResult.submittedTagValues,
      revision: previousState.revision + 1,
    };
  }

  const { data, error } = rpcResult;

  if (error) {
    if (error?.code === "22023") {
      return updatePostErrorState(
        supabase,
        newImagePaths,
        previousState,
        tagsResult.submittedTagValues,
        {
          error: "投稿内容を保存できませんでした。入力内容を確認してください。",
          fieldErrors: {
            images: "画像の選択内容が最新の投稿状態と一致しません。",
          },
        },
      );
    }

    return updatePostErrorState(
      supabase,
      newImagePaths,
      previousState,
      tagsResult.submittedTagValues,
      {
        error:
          "投稿を更新できませんでした。投稿またはアカウントの状態を確認してください。",
      },
    );
  }

  const updateResult = parseUpdatePostRpcResult(
    data,
    postIdValue,
    userId,
  );
  const cleanupSucceeded = updateResult
    ? await cleanupPostImageUploads(
        supabase,
        updateResult.removedImagePaths,
      )
    : false;

  revalidatePath("/home");
  revalidatePath("/profile");
  revalidatePath("/profile/posts");
  revalidatePath(`/posts/${postIdValue}`);
  revalidatePath(`/posts/${postIdValue}/edit`);
  revalidatePath(`/users/${userId}`);

  return {
    cleanupWarning: !cleanupSucceeded,
    error: null,
    fieldErrors: {},
    submittedTagValues: tagsResult.submittedTagValues,
    revision: previousState.revision + 1,
    updatedPostId: postIdValue,
  };
}

export async function deletePost(
  _previousState: DeletePostActionState,
  formData: FormData,
): Promise<DeletePostActionState> {
  const postIdValue = formData.get("postId");

  if (typeof postIdValue !== "string" || !isUuid(postIdValue)) {
    return { error: "削除する投稿を確認できませんでした。" };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
    };
  }

  const { data, error } = await supabase.rpc(
    "my_diary_soft_delete_post",
    {
      target_post_id: postIdValue,
    },
  );

  if (error) {
    return {
      error:
        error.code === "42501"
          ? "この投稿を削除する権限がありません。"
          : "投稿の削除に失敗しました。時間をおいてもう一度お試しください。",
    };
  }

  if (data !== true) {
    return {
      error:
        "投稿を削除できませんでした。投稿またはアカウントの状態を確認してください。",
    };
  }

  revalidatePath("/profile");
  revalidatePath("/profile/posts");
  revalidatePath(`/users/${userId}`);
  return { error: null };
}

export async function toggleReaction(
  _previousState: ToggleReactionActionState,
  formData: FormData,
): Promise<ToggleReactionActionState> {
  const postIdValue = formData.get("postId");
  const reactionTypeValue = formData.get("reactionType");

  if (typeof postIdValue !== "string" || !isUuid(postIdValue)) {
    return { error: "リアクションする投稿を確認できませんでした。" };
  }

  if (
    typeof reactionTypeValue !== "string" ||
    !isReactionType(reactionTypeValue)
  ) {
    return { error: "リアクションの種類を確認できませんでした。" };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
    };
  }

  const accountResult = await supabase
    .from("accounts")
    .select("status")
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle<{ status: string }>();

  if (accountResult.error) {
    return {
      error:
        "アカウントの状態を確認できませんでした。時間をおいてもう一度お試しください。",
    };
  }

  if (accountResult.data?.status !== "active") {
    return {
      error: "現在のアカウント状態ではリアクションを変更できません。",
    };
  }

  const postResult = await supabase
    .from("posts")
    .select("id, user_id")
    .eq("id", postIdValue)
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle<{ id: string; user_id: string }>();

  if (postResult.error) {
    return {
      error:
        "日記の状態を確認できませんでした。時間をおいてもう一度お試しください。",
    };
  }

  if (!postResult.data) {
    return {
      error: "この日記は現在表示できないため、リアクションできません。",
    };
  }

  const currentResult = await supabase
    .from("reactions")
    .select("id, reaction_type")
    .eq("post_id", postIdValue)
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle<{ id: string; reaction_type: ReactionType }>();

  if (currentResult.error) {
    return {
      error:
        "リアクションを確認できませんでした。時間をおいてもう一度お試しください。",
    };
  }

  let mutationResult:
    | { data: { id: string } | null; error: { code?: string } | null }
    | undefined;

  if (currentResult.data?.reaction_type === reactionTypeValue) {
    mutationResult = await supabase
      .from("reactions")
      .delete()
      .eq("id", currentResult.data.id)
      .eq("user_id", userId)
      .select("id")
      .maybeSingle<{ id: string }>();
  } else if (currentResult.data) {
    mutationResult = await supabase
      .from("reactions")
      .update({ reaction_type: reactionTypeValue })
      .eq("id", currentResult.data.id)
      .eq("user_id", userId)
      .select("id")
      .maybeSingle<{ id: string }>();
  } else {
    mutationResult = await supabase
      .from("reactions")
      .insert({
        post_id: postIdValue,
        user_id: userId,
        reaction_type: reactionTypeValue,
      })
      .select("id")
      .maybeSingle<{ id: string }>();
  }

  if (mutationResult.error || !mutationResult.data) {
    return {
      error: "リアクションを更新できませんでした。もう一度お試しください。",
    };
  }

  revalidatePath("/home");
  revalidatePath("/profile/posts");
  revalidatePath(`/posts/${postIdValue}`);
  revalidatePath(`/users/${postResult.data.user_id}`);

  return { error: null };
}

export async function createComment(
  _previousState: CreateCommentActionState,
  formData: FormData,
): Promise<CreateCommentActionState> {
  const postIdValue = formData.get("postId");
  const bodyValue = formData.get("body");

  if (typeof postIdValue !== "string" || !isUuid(postIdValue)) {
    return {
      error: "コメントする日記を確認できませんでした。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  if (typeof bodyValue !== "string") {
    return {
      error: "入力内容を確認してください。",
      fieldError: "コメントを入力してください。",
      createdCommentId: null,
    };
  }

  const body = bodyValue.trim();

  if (characterCount(body) < 1) {
    return {
      error: "入力内容を確認してください。",
      fieldError: "コメントを入力してください。",
      createdCommentId: null,
    };
  }

  if (characterCount(body) > COMMENT_MAX_LENGTH) {
    return {
      error: "入力内容を確認してください。",
      fieldError: `コメントは${COMMENT_MAX_LENGTH.toLocaleString("ja-JP")}文字以下で入力してください。`,
      createdCommentId: null,
    };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  const accountResult = await supabase
    .from("accounts")
    .select("status")
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle<{ status: string }>();

  if (accountResult.error) {
    return {
      error:
        "アカウントの状態を確認できませんでした。時間をおいてもう一度お試しください。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  if (accountResult.data?.status !== "active") {
    return {
      error: "現在のアカウント状態ではコメントを投稿できません。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  const postResult = await supabase
    .from("posts")
    .select("id, user_id")
    .eq("id", postIdValue)
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle<{ id: string; user_id: string }>();

  if (postResult.error) {
    return {
      error:
        "日記の状態を確認できませんでした。時間をおいてもう一度お試しください。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  if (!postResult.data) {
    return {
      error: "この日記は現在表示できないため、コメントできません。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  const { data, error } = await supabase
    .from("comments")
    .insert({
      post_id: postIdValue,
      user_id: userId,
      body,
    })
    .select("id")
    .maybeSingle<{ id: string }>();

  if (error || !data) {
    return {
      error: "コメントを投稿できませんでした。もう一度お試しください。",
      fieldError: null,
      createdCommentId: null,
    };
  }

  revalidatePath("/home");
  revalidatePath("/profile/posts");
  revalidatePath(`/posts/${postIdValue}`);
  revalidatePath(`/users/${postResult.data.user_id}`);

  return {
    error: null,
    fieldError: null,
    createdCommentId: data.id,
  };
}

export async function deleteComment(
  _previousState: DeleteCommentActionState,
  formData: FormData,
): Promise<DeleteCommentActionState> {
  const commentIdValue = formData.get("commentId");
  const postIdValue = formData.get("postId");

  if (
    typeof commentIdValue !== "string" ||
    !isUuid(commentIdValue) ||
    typeof postIdValue !== "string" ||
    !isUuid(postIdValue)
  ) {
    return { error: "削除するコメントを確認できませんでした。" };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
    };
  }

  const accountResult = await supabase
    .from("accounts")
    .select("status")
    .eq("user_id", userId)
    .limit(1)
    .maybeSingle<{ status: string }>();

  if (accountResult.error) {
    return {
      error:
        "アカウントの状態を確認できませんでした。時間をおいてもう一度お試しください。",
    };
  }

  if (accountResult.data?.status !== "active") {
    return {
      error: "現在のアカウント状態ではコメントを削除できません。",
    };
  }

  const postResult = await supabase
    .from("posts")
    .select("id, user_id")
    .eq("id", postIdValue)
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle<{ id: string; user_id: string }>();

  if (postResult.error || !postResult.data) {
    return {
      error: "コメントを削除できませんでした。もう一度お試しください。",
    };
  }

  const { data, error } = await supabase.rpc(
    "my_diary_soft_delete_comment",
    {
      target_comment_id: commentIdValue,
    },
  );

  if (error || data !== true) {
    return {
      error: "コメントを削除できませんでした。もう一度お試しください。",
    };
  }

  revalidatePath("/home");
  revalidatePath("/profile/posts");
  revalidatePath(`/posts/${postIdValue}`);
  revalidatePath(`/users/${postResult.data.user_id}`);

  return { error: null };
}
