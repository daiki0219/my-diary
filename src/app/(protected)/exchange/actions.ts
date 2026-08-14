"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export type ExchangeActionState = {
  error: string | null;
  completed: boolean;
  message: string | null;
  revision: number;
};

const AUTH_ERROR =
  "ログイン状態を確認できませんでした。もう一度ログインしてください。";
const INPUT_ERROR = "操作の対象を確認できませんでした。";
const SELF_ERROR = "自分自身を交換日記に招待することはできません。";
const OPERATION_ERROR =
  "現在この操作を完了できません。状態を更新して、少し時間をおいてもう一度お試しください。";

function errorState(
  previousState: ExchangeActionState,
  error: string,
): ExchangeActionState {
  return {
    error,
    completed: false,
    message: null,
    revision: previousState.revision + 1,
  };
}

function completedState(
  previousState: ExchangeActionState,
): ExchangeActionState {
  return {
    error: null,
    completed: true,
    message: "設定を更新しました。",
    revision: previousState.revision + 1,
  };
}

function getUuid(formData: FormData, fieldName: string) {
  const value = formData.get(fieldName);

  return typeof value === "string" && isUuid(value)
    ? value.toLowerCase()
    : null;
}

async function getAuthenticatedContext() {
  try {
    const supabase = await createClient();
    const claimsResult = await supabase.auth.getClaims().catch(() => null);
    const currentUserId = claimsResult?.data?.claims?.sub;

    if (
      !claimsResult ||
      claimsResult.error ||
      typeof currentUserId !== "string" ||
      !isUuid(currentUserId)
    ) {
      return null;
    }

    return {
      supabase,
      currentUserId: currentUserId.toLowerCase(),
    };
  } catch {
    return null;
  }
}

function revalidateExchangeViews() {
  revalidatePath("/exchange");
  revalidatePath("/home");
}

function revalidateNotificationViews() {
  revalidatePath("/notifications");
  revalidatePath("/home");
}

function revalidateProfileExchangeViews(targetUserId: string) {
  revalidatePath(`/users/${targetUserId}`);
  revalidatePath("/exchange");
}

export async function createExchangeInvitation(
  previousState: ExchangeActionState,
  formData: FormData,
): Promise<ExchangeActionState> {
  const targetUserId = getUuid(formData, "targetUserId");

  if (!targetUserId) {
    return errorState(previousState, INPUT_ERROR);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return errorState(previousState, AUTH_ERROR);
  }

  if (context.currentUserId === targetUserId) {
    return errorState(previousState, SELF_ERROR);
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_create_exchange_invitation",
      { p_invitee_user_id: targetUserId },
    );
  } catch {
    return errorState(previousState, OPERATION_ERROR);
  }

  if (
    result.error ||
    typeof result.data !== "string" ||
    !isUuid(result.data)
  ) {
    return errorState(previousState, OPERATION_ERROR);
  }

  revalidateExchangeViews();
  revalidateNotificationViews();
  revalidatePath(`/users/${targetUserId}`);
  redirect("/exchange?view=invitations");
}

export async function acceptExchangeInvitation(
  previousState: ExchangeActionState,
  formData: FormData,
): Promise<ExchangeActionState> {
  const invitationId = getUuid(formData, "invitationId");

  if (!invitationId) {
    return errorState(previousState, INPUT_ERROR);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return errorState(previousState, AUTH_ERROR);
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_accept_exchange_invitation",
      { p_invitation_id: invitationId },
    );
  } catch {
    return errorState(previousState, OPERATION_ERROR);
  }

  if (
    result.error ||
    typeof result.data !== "string" ||
    !isUuid(result.data)
  ) {
    return errorState(previousState, OPERATION_ERROR);
  }

  const diaryId = result.data.toLowerCase();
  revalidateExchangeViews();
  revalidateNotificationViews();
  redirect(`/exchange/${diaryId}`);
}

export async function rejectExchangeInvitation(
  previousState: ExchangeActionState,
  formData: FormData,
): Promise<ExchangeActionState> {
  return runTerminalInvitationAction(
    previousState,
    formData,
    "my_diary_reject_exchange_invitation",
  );
}

export async function cancelExchangeInvitation(
  previousState: ExchangeActionState,
  formData: FormData,
): Promise<ExchangeActionState> {
  return runTerminalInvitationAction(
    previousState,
    formData,
    "my_diary_cancel_exchange_invitation",
  );
}

async function runTerminalInvitationAction(
  previousState: ExchangeActionState,
  formData: FormData,
  rpcName:
    | "my_diary_reject_exchange_invitation"
    | "my_diary_cancel_exchange_invitation",
): Promise<ExchangeActionState> {
  const invitationId = getUuid(formData, "invitationId");

  if (!invitationId) {
    return errorState(previousState, INPUT_ERROR);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return errorState(previousState, AUTH_ERROR);
  }

  let result;

  try {
    result = await context.supabase.rpc(rpcName, {
      p_invitation_id: invitationId,
    });
  } catch {
    return errorState(previousState, OPERATION_ERROR);
  }

  if (result.error || result.data !== true) {
    return errorState(previousState, OPERATION_ERROR);
  }

  revalidateExchangeViews();
  redirect("/exchange?view=invitations");
}

export async function blockExchangeInvitationsFromUser(
  previousState: ExchangeActionState,
  formData: FormData,
): Promise<ExchangeActionState> {
  return runBlockSettingAction(
    previousState,
    formData,
    "my_diary_block_exchange_invitations_from_user",
  );
}

export async function unblockExchangeInvitationsFromUser(
  previousState: ExchangeActionState,
  formData: FormData,
): Promise<ExchangeActionState> {
  return runBlockSettingAction(
    previousState,
    formData,
    "my_diary_unblock_exchange_invitations_from_user",
  );
}

async function runBlockSettingAction(
  previousState: ExchangeActionState,
  formData: FormData,
  rpcName:
    | "my_diary_block_exchange_invitations_from_user"
    | "my_diary_unblock_exchange_invitations_from_user",
): Promise<ExchangeActionState> {
  const targetUserId = getUuid(formData, "targetUserId");

  if (!targetUserId) {
    return errorState(previousState, INPUT_ERROR);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return errorState(previousState, AUTH_ERROR);
  }

  if (context.currentUserId === targetUserId) {
    return errorState(previousState, SELF_ERROR);
  }

  let result;

  try {
    result = await context.supabase.rpc(rpcName, {
      p_user_id: targetUserId,
    });
  } catch {
    return errorState(previousState, OPERATION_ERROR);
  }

  if (result.error || result.data !== true) {
    return errorState(previousState, OPERATION_ERROR);
  }

  revalidateProfileExchangeViews(targetUserId);
  return completedState(previousState);
}
