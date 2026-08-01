"use server";

import { revalidatePath } from "next/cache";

import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export type FollowActionState = {
  error: string | null;
  success: boolean;
};

const INITIAL_ERROR =
  "ログイン状態を確認できませんでした。もう一度ログインしてください。";

async function getFollowContext(formData: FormData) {
  const targetUserIdValue = formData.get("targetUserId");

  if (
    typeof targetUserIdValue !== "string" ||
    !isUuid(targetUserIdValue)
  ) {
    return {
      error: "フォローするユーザーを確認できませんでした。",
    } as const;
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    return { error: INITIAL_ERROR } as const;
  }

  if (currentUserId.toLowerCase() === targetUserIdValue.toLowerCase()) {
    return { error: "自分自身をフォローすることはできません。" } as const;
  }

  const [accountResult, profileResult] = await Promise.all([
    supabase
      .from("accounts")
      .select("status")
      .eq("user_id", currentUserId)
      .limit(1)
      .maybeSingle<{ status: string }>(),
    supabase
      .from("profiles")
      .select("user_id")
      .eq("user_id", targetUserIdValue)
      .limit(1)
      .maybeSingle<{ user_id: string }>(),
  ]);

  if (accountResult.error || profileResult.error) {
    return {
      error:
        "ユーザーの状態を確認できませんでした。時間をおいてもう一度お試しください。",
    } as const;
  }

  if (accountResult.data?.status !== "active") {
    return {
      error: "現在のアカウント状態ではフォローを変更できません。",
    } as const;
  }

  if (!profileResult.data) {
    return {
      error: "フォローするユーザーが見つかりませんでした。",
    } as const;
  }

  return {
    error: null,
    supabase,
    currentUserId,
    targetUserId: targetUserIdValue,
  } as const;
}

function revalidateFollowViews(
  currentUserId: string,
  targetUserId: string,
) {
  revalidatePath("/home");
  revalidatePath("/profile");
  revalidatePath(`/users/${targetUserId}`);
  revalidatePath("/search");
  revalidatePath("/profile/following");
  revalidatePath(`/users/${currentUserId}/following`);
  revalidatePath(`/users/${targetUserId}/followers`);
}

export async function followUser(
  _previousState: FollowActionState,
  formData: FormData,
): Promise<FollowActionState> {
  const context = await getFollowContext(formData);

  if (context.error) {
    return { error: context.error, success: false };
  }

  const currentResult = await context.supabase
    .from("follows")
    .select("following_id")
    .eq("follower_id", context.currentUserId)
    .eq("following_id", context.targetUserId)
    .limit(1)
    .maybeSingle<{ following_id: string }>();

  if (currentResult.error) {
    return {
      error: "フォロー状態を確認できませんでした。もう一度お試しください。",
      success: false,
    };
  }

  if (currentResult.data) {
    return {
      error: "このユーザーはすでにフォローしています。",
      success: false,
    };
  }

  const { data, error } = await context.supabase
    .from("follows")
    .insert({
      follower_id: context.currentUserId,
      following_id: context.targetUserId,
    })
    .select("following_id")
    .maybeSingle<{ following_id: string }>();

  if (error || !data) {
    return {
      error: "フォローできませんでした。もう一度お試しください。",
      success: false,
    };
  }

  revalidateFollowViews(context.currentUserId, context.targetUserId);
  return { error: null, success: true };
}

export async function unfollowUser(
  _previousState: FollowActionState,
  formData: FormData,
): Promise<FollowActionState> {
  const context = await getFollowContext(formData);

  if (context.error) {
    return { error: context.error, success: false };
  }

  const currentResult = await context.supabase
    .from("follows")
    .select("following_id")
    .eq("follower_id", context.currentUserId)
    .eq("following_id", context.targetUserId)
    .limit(1)
    .maybeSingle<{ following_id: string }>();

  if (currentResult.error) {
    return {
      error: "フォロー状態を確認できませんでした。もう一度お試しください。",
      success: false,
    };
  }

  if (!currentResult.data) {
    return {
      error: "このユーザーは現在フォローしていません。",
      success: false,
    };
  }

  const { data, error } = await context.supabase
    .from("follows")
    .delete()
    .eq("follower_id", context.currentUserId)
    .eq("following_id", context.targetUserId)
    .select("following_id")
    .maybeSingle<{ following_id: string }>();

  if (error || !data) {
    return {
      error: "フォローを解除できませんでした。もう一度お試しください。",
      success: false,
    };
  }

  revalidateFollowViews(context.currentUserId, context.targetUserId);
  return { error: null, success: true };
}
