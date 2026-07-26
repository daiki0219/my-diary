"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  isPostMood,
  isPostVisibility,
  type PostMood,
} from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
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

export type DeletePostActionState = {
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
