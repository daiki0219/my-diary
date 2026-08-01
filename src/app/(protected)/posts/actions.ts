"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { COMMENT_MAX_LENGTH } from "@/lib/comment-data";
import {
  isPostMood,
  isPostVisibility,
  type PostMood,
} from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
import {
  isReactionType,
  type ReactionType,
} from "@/lib/reaction-data";
import { createClient } from "@/lib/supabase/server";

export type CreatePostActionState = {
  error: string | null;
  fieldErrors: {
    title?: string;
    body?: string;
    mood?: string;
    visibility?: string;
  };
};

export type UpdatePostActionState = CreatePostActionState;

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

export async function createPost(
  _previousState: CreatePostActionState,
  formData: FormData,
): Promise<CreatePostActionState> {
  const titleValue = formData.get("title");
  const bodyValue = formData.get("body");
  const moodValue = formData.get("mood");
  const visibilityValue = formData.get("visibility");
  const fieldErrors: CreatePostActionState["fieldErrors"] = {};

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

  if (Object.keys(fieldErrors).length > 0) {
    return { error: "入力内容を確認してください。", fieldErrors };
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
    return { error: "入力内容を確認してください。", fieldErrors };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
      fieldErrors: {},
    };
  }

  const { data, error } = await supabase
    .from("posts")
    .insert({
      user_id: userId,
      title,
      body,
      mood: mood as PostMood | null,
      visibility,
    })
    .select("id")
    .maybeSingle();

  if (!error && !data) {
    return {
      error:
        "投稿を作成できませんでした。アカウントの状態を確認してください。",
      fieldErrors: {},
    };
  }

  if (error) {
    return {
      error:
        error.code === "42501"
          ? "投稿を作成する権限がありません。アカウントの状態を確認してください。"
          : "投稿に失敗しました。時間をおいてもう一度お試しください。",
      fieldErrors: {},
    };
  }

  revalidatePath("/profile");
  revalidatePath("/profile/posts");
  revalidatePath(`/users/${userId}`);
  redirect("/profile/posts?status=created");
}

export async function updatePost(
  _previousState: UpdatePostActionState,
  formData: FormData,
): Promise<UpdatePostActionState> {
  const postIdValue = formData.get("postId");
  const titleValue = formData.get("title");
  const bodyValue = formData.get("body");
  const moodValue = formData.get("mood");
  const visibilityValue = formData.get("visibility");
  const fieldErrors: UpdatePostActionState["fieldErrors"] = {};

  if (typeof postIdValue !== "string" || !isUuid(postIdValue)) {
    return {
      error: "更新する投稿を確認できませんでした。",
      fieldErrors,
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

  if (Object.keys(fieldErrors).length > 0) {
    return { error: "入力内容を確認してください。", fieldErrors };
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
    return { error: "入力内容を確認してください。", fieldErrors };
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    return {
      error: "ログイン状態を確認できませんでした。もう一度ログインしてください。",
      fieldErrors: {},
    };
  }

  const { data, error } = await supabase
    .from("posts")
    .update({
      title,
      body,
      mood: mood as PostMood | null,
      visibility,
    })
    .eq("id", postIdValue)
    .eq("user_id", userId)
    .is("deleted_at", null)
    .select("id")
    .maybeSingle<{ id: string }>();

  if (error || !data) {
    return {
      error:
        "投稿を更新できませんでした。投稿またはアカウントの状態を確認してください。",
      fieldErrors: {},
    };
  }

  revalidatePath("/home");
  revalidatePath("/profile");
  revalidatePath("/profile/posts");
  revalidatePath(`/posts/${postIdValue}`);
  revalidatePath(`/posts/${postIdValue}/edit`);
  revalidatePath(`/users/${userId}`);
  redirect(`/posts/${postIdValue}?status=updated`);
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
