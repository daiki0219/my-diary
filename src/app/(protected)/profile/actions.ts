"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export type ProfileActionState = {
  error: string | null;
  fieldErrors: {
    username?: string;
    bio?: string;
  };
};

function characterCount(value: string) {
  return Array.from(value).length;
}

export async function updateProfile(
  _previousState: ProfileActionState,
  formData: FormData,
): Promise<ProfileActionState> {
  const usernameValue = formData.get("username");
  const bioValue = formData.get("bio");
  const fieldErrors: ProfileActionState["fieldErrors"] = {};

  if (typeof usernameValue !== "string") {
    fieldErrors.username = "ユーザー名を入力してください。";
  }

  if (bioValue !== null && typeof bioValue !== "string") {
    fieldErrors.bio = "自己紹介を正しく入力してください。";
  }

  if (Object.keys(fieldErrors).length > 0) {
    return { error: "入力内容を確認してください。", fieldErrors };
  }

  const username = (usernameValue as string).trim();
  const normalizedBio =
    typeof bioValue === "string" ? bioValue.trim() : "";
  const bio = normalizedBio || null;

  if (characterCount(username) < 1 || characterCount(username) > 50) {
    fieldErrors.username =
      "ユーザー名は1文字以上50文字以下で入力してください。";
  }

  if (bio !== null && characterCount(bio) > 500) {
    fieldErrors.bio = "自己紹介は500文字以下で入力してください。";
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
    .from("profiles")
    .update({ username, bio })
    .eq("user_id", userId)
    .select("user_id")
    .maybeSingle();

  if (!error && !data) {
    return {
      error:
        "プロフィールを更新できませんでした。更新権限またはプロフィールの状態を確認してください。",
      fieldErrors: {},
    };
  }

  if (error) {
    return {
      error:
        error.code === "42501"
          ? "プロフィールを更新する権限がありません。"
          : "プロフィールの保存に失敗しました。時間をおいてもう一度お試しください。",
      fieldErrors: {},
    };
  }

  revalidatePath("/profile");
  revalidatePath(`/users/${userId}`);
  redirect("/profile?status=updated");
}
