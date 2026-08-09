"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getNotificationOpenTarget } from "@/lib/notification-data";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export type NotificationActionState = {
  error: string | null;
  completed: boolean;
  unavailable: boolean;
  revision: number;
};

const AUTH_ERROR =
  "ログイン状態を確認できませんでした。もう一度ログインしてください。";
const UPDATE_ERROR =
  "通知を更新できませんでした。時間をおいてもう一度お試しください。";

function getNotificationId(formData: FormData) {
  const value = formData.get("notificationId");

  return typeof value === "string" && isUuid(value) ? value : null;
}

async function getAuthenticatedClient() {
  const supabase = await createClient();
  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const userId = claimsResult?.data?.claims?.sub;

  if (
    !claimsResult ||
    claimsResult.error ||
    typeof userId !== "string" ||
    userId.length === 0
  ) {
    return null;
  }

  return supabase;
}

function revalidateNotificationViews() {
  revalidatePath("/notifications");
  revalidatePath("/home");
}

export async function markNotificationRead(
  previousState: NotificationActionState,
  formData: FormData,
): Promise<NotificationActionState> {
  const notificationId = getNotificationId(formData);

  if (!notificationId) {
    return {
      error: "通知を確認できませんでした。",
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  const supabase = await getAuthenticatedClient();

  if (!supabase) {
    return {
      error: AUTH_ERROR,
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  const result = await supabase
    .from("notifications")
    .update({ is_read: true })
    .eq("id", notificationId)
    .select("id")
    .limit(1)
    .maybeSingle<{ id: string }>();

  if (result.error || !result.data) {
    return {
      error: UPDATE_ERROR,
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  revalidateNotificationViews();
  return {
    error: null,
    completed: true,
    unavailable: false,
    revision: previousState.revision + 1,
  };
}

export async function openNotification(
  previousState: NotificationActionState,
  formData: FormData,
): Promise<NotificationActionState> {
  const notificationId = getNotificationId(formData);

  if (!notificationId) {
    return {
      error: "通知を確認できませんでした。",
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  const supabase = await getAuthenticatedClient();

  if (!supabase) {
    return {
      error: AUTH_ERROR,
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  const targetResult = await getNotificationOpenTarget(
    supabase,
    notificationId,
  );

  if (targetResult.error || !targetResult.data) {
    return {
      error:
        "この通知を現在開くことができません。通知一覧を更新してもう一度お試しください。",
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  const updateResult = await supabase
    .from("notifications")
    .update({ is_read: true })
    .eq("id", targetResult.data.id)
    .select("id")
    .limit(1)
    .maybeSingle<{ id: string }>();

  if (updateResult.error || !updateResult.data) {
    return {
      error: UPDATE_ERROR,
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  revalidateNotificationViews();

  if (!targetResult.data.targetUrl) {
    return {
      error: null,
      completed: true,
      unavailable: true,
      revision: previousState.revision + 1,
    };
  }

  redirect(targetResult.data.targetUrl);
}

export async function markAllNotificationsRead(
  previousState: NotificationActionState,
): Promise<NotificationActionState> {
  const supabase = await getAuthenticatedClient();

  if (!supabase) {
    return {
      error: AUTH_ERROR,
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  const result = await supabase
    .from("notifications")
    .update({ is_read: true })
    .eq("is_read", false);

  if (result.error) {
    return {
      error:
        "通知をすべて既読にできませんでした。時間をおいてもう一度お試しください。",
      completed: false,
      unavailable: false,
      revision: previousState.revision + 1,
    };
  }

  revalidateNotificationViews();
  return {
    error: null,
    completed: true,
    unavailable: false,
    revision: previousState.revision + 1,
  };
}
