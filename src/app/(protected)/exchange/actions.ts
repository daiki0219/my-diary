"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import {
  getUnicodeCodePointCount,
  validateDiaryEntryFormData,
  type DiaryEntryFieldErrors,
} from "@/lib/diary-entry-validation";
import {
  EXCHANGE_ENTRY_IMAGE_MAX_COUNT,
  isExchangeEntryImageStoragePathFor,
  parseExchangeEntryImageStoragePath,
} from "@/lib/exchange-entry-image-input";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export type ExchangeActionState = {
  error: string | null;
  completed: boolean;
  message: string | null;
  revision: number;
};

export type ExchangeEntryActionState = {
  error: string | null;
  fieldErrors: DiaryEntryFieldErrors & { images?: string };
  submittedTagValues: string[];
  revision: number;
  createOutcome?:
    | "idle"
    | "safe-to-cleanup"
    | "unknown-outcome"
    | "committed";
  createdEntryId?: string;
};

export type ExchangeDiaryTitleActionState = {
  error: string | null;
  fieldError: string | null;
  completed: boolean;
  normalizedTitle: string;
  revision: number;
};

export type ExchangeDiaryMutationActionState = {
  error: string | null;
  completed: boolean;
  revision: number;
};

const AUTH_ERROR =
  "ログイン状態を確認できませんでした。もう一度ログインしてください。";
const INPUT_ERROR = "操作の対象を確認できませんでした。";
const SELF_ERROR = "自分自身を交換日記に招待することはできません。";
const OPERATION_ERROR =
  "現在この操作を完了できません。状態を更新して、少し時間をおいてもう一度お試しください。";
const ENTRY_OPERATION_ERROR =
  "現在この日記を保存できません。状態を更新して、少し時間をおいてもう一度お試しください。";
const DIARY_MUTATION_ERROR =
  "現在この交換日記を更新できません。状態を更新して、少し時間をおいてもう一度お試しください。";
const ENTRY_DELETE_ERROR =
  "現在この日記を削除できません。状態を更新して、少し時間をおいてもう一度お試しください。";
const EXCHANGE_ENTRY_CREATE_ROLLBACK_CODES = new Set([
  "22023",
  "40001",
  "42501",
]);

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

function entryErrorState(
  previousState: ExchangeEntryActionState,
  error: string,
  options?: {
    fieldErrors?: DiaryEntryFieldErrors;
    submittedTagValues?: string[];
  },
): ExchangeEntryActionState {
  return {
    error,
    fieldErrors: options?.fieldErrors ?? {},
    submittedTagValues:
      options?.submittedTagValues ?? previousState.submittedTagValues,
    revision: previousState.revision + 1,
  };
}

function createEntryErrorState(
  previousState: ExchangeEntryActionState,
  error: string,
  createOutcome: "safe-to-cleanup" | "unknown-outcome",
  options?: {
    fieldErrors?: ExchangeEntryActionState["fieldErrors"];
    submittedTagValues?: string[];
  },
): ExchangeEntryActionState {
  return {
    error,
    fieldErrors: options?.fieldErrors ?? {},
    submittedTagValues:
      options?.submittedTagValues ?? previousState.submittedTagValues,
    revision: previousState.revision + 1,
    createOutcome,
  };
}

function diaryMutationErrorState(
  previousState: ExchangeDiaryMutationActionState,
  error: string,
): ExchangeDiaryMutationActionState {
  return {
    error,
    completed: false,
    revision: previousState.revision + 1,
  };
}

function diaryMutationCompletedState(
  previousState: ExchangeDiaryMutationActionState,
): ExchangeDiaryMutationActionState {
  return {
    error: null,
    completed: true,
    revision: previousState.revision + 1,
  };
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

async function exchangeEntryBelongsToDiary(
  supabase: Awaited<ReturnType<typeof createClient>>,
  diaryId: string,
  entryId: string,
) {
  try {
    const result = await supabase
      .from("exchange_entries")
      .select("id")
      .eq("id", entryId)
      .eq("diary_id", diaryId)
      .limit(2)
      .returns<unknown[]>();

    return (
      !result.error &&
      result.data?.length === 1 &&
      typeof result.data[0] === "object" &&
      result.data[0] !== null &&
      "id" in result.data[0] &&
      typeof result.data[0].id === "string" &&
      result.data[0].id.toLowerCase() === entryId
    );
  } catch {
    return false;
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

function revalidateExchangeEntryViews(diaryId: string) {
  revalidatePath("/exchange");
  revalidatePath(`/exchange/${diaryId}`);
  revalidatePath("/notifications");
  revalidatePath("/home");
}

function revalidateExchangeDiaryMutationViews(diaryId: string) {
  revalidatePath("/exchange");
  revalidatePath(`/exchange/${diaryId}`);
  revalidatePath("/home");
}

export async function createExchangeEntry(
  previousState: ExchangeEntryActionState,
  formData: FormData,
): Promise<ExchangeEntryActionState> {
  const diaryId = getUuid(formData, "diaryId");
  const entryId = getUuid(formData, "entryId");
  const imagePathEntries = formData.getAll("imagePaths");
  const imagePaths = imagePathEntries.filter(
    (entry): entry is string => typeof entry === "string",
  );
  const validation = validateDiaryEntryFormData(formData);

  if (!diaryId || !entryId) {
    return createEntryErrorState(
      previousState,
      INPUT_ERROR,
      "safe-to-cleanup",
      {
        fieldErrors: { images: "画像の送信内容を確認できませんでした。" },
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  if (
    imagePathEntries.length !== imagePaths.length ||
    imagePaths.length > EXCHANGE_ENTRY_IMAGE_MAX_COUNT ||
    new Set(imagePaths).size !== imagePaths.length
  ) {
    return createEntryErrorState(
      previousState,
      "入力内容を確認してください。",
      "safe-to-cleanup",
      {
        fieldErrors: { images: "画像の送信内容を確認できませんでした。" },
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  if (!validation.data) {
    return createEntryErrorState(
      previousState,
      "入力内容を確認してください。",
      "safe-to-cleanup",
      {
        fieldErrors: validation.fieldErrors,
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return createEntryErrorState(
      previousState,
      AUTH_ERROR,
      "safe-to-cleanup",
      {
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  const imagePathsAreValid = imagePaths.every((path) => {
    const parsed = parseExchangeEntryImageStoragePath(path);

    return (
      parsed !== null &&
      isExchangeEntryImageStoragePathFor(path, {
        ownerUserId: context.currentUserId,
        diaryId,
        entryId,
        imageId: parsed.imageId,
      })
    );
  });

  if (!imagePathsAreValid) {
    return createEntryErrorState(
      previousState,
      "入力内容を確認してください。",
      "safe-to-cleanup",
      {
        fieldErrors: { images: "画像の送信内容を確認できませんでした。" },
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_create_exchange_entry_with_images",
      {
        p_entry_id: entryId,
        p_diary_id: diaryId,
        p_title: validation.data.title,
        p_body: validation.data.body,
        p_mood: validation.data.mood,
        p_location_name: validation.data.locationName,
        p_tags: validation.data.tags,
        p_image_paths: imagePaths,
      },
    );
  } catch {
    return createEntryErrorState(
      previousState,
      "通信が途切れ、保存結果を確認できませんでした。画像は削除していません。交換日記を再読み込みして保存結果を確認してください。",
      "unknown-outcome",
      {
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  if (result.error) {
    const rollbackIsExplicit = EXCHANGE_ENTRY_CREATE_ROLLBACK_CODES.has(
      result.error.code,
    );

    return createEntryErrorState(
      previousState,
      rollbackIsExplicit
        ? ENTRY_OPERATION_ERROR
        : "通信状態のため保存結果を確認できませんでした。画像は削除していません。交換日記を再読み込みして保存結果を確認してください。",
      rollbackIsExplicit ? "safe-to-cleanup" : "unknown-outcome",
      {
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  if (
    typeof result.data !== "string" ||
    result.data.toLowerCase() !== entryId
  ) {
    return createEntryErrorState(
      previousState,
      "保存結果を確認できませんでした。画像は削除していません。交換日記を再読み込みして保存結果を確認してください。",
      "unknown-outcome",
      {
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  try {
    revalidateExchangeEntryViews(diaryId);
  } catch {
    return createEntryErrorState(
      previousState,
      "日記は保存された可能性があります。画像は削除していません。交換日記を再読み込みして保存結果を確認してください。",
      "unknown-outcome",
      {
        submittedTagValues: validation.submittedTagValues,
      },
    );
  }

  return {
    error: null,
    fieldErrors: {},
    submittedTagValues: validation.submittedTagValues,
    revision: previousState.revision + 1,
    createOutcome: "committed",
    createdEntryId: entryId,
  };
}

export async function updateExchangeEntry(
  previousState: ExchangeEntryActionState,
  formData: FormData,
): Promise<ExchangeEntryActionState> {
  const diaryId = getUuid(formData, "diaryId");
  const entryId = getUuid(formData, "entryId");
  const validation = validateDiaryEntryFormData(formData);

  if (!diaryId || !entryId) {
    return entryErrorState(previousState, INPUT_ERROR, {
      submittedTagValues: validation.submittedTagValues,
    });
  }

  if (!validation.data) {
    return entryErrorState(previousState, "入力内容を確認してください。", {
      fieldErrors: validation.fieldErrors,
      submittedTagValues: validation.submittedTagValues,
    });
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return entryErrorState(previousState, AUTH_ERROR, {
      submittedTagValues: validation.submittedTagValues,
    });
  }

  if (
    !(await exchangeEntryBelongsToDiary(
      context.supabase,
      diaryId,
      entryId,
    ))
  ) {
    return entryErrorState(previousState, ENTRY_OPERATION_ERROR, {
      submittedTagValues: validation.submittedTagValues,
    });
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_update_exchange_entry",
      {
        p_entry_id: entryId,
        p_title: validation.data.title,
        p_body: validation.data.body,
        p_mood: validation.data.mood,
        p_location_name: validation.data.locationName,
        p_tags: validation.data.tags,
      },
    );
  } catch {
    return entryErrorState(previousState, ENTRY_OPERATION_ERROR, {
      submittedTagValues: validation.submittedTagValues,
    });
  }

  if (
    result.error ||
    typeof result.data !== "string" ||
    result.data.toLowerCase() !== entryId
  ) {
    return entryErrorState(previousState, ENTRY_OPERATION_ERROR, {
      submittedTagValues: validation.submittedTagValues,
    });
  }

  revalidateExchangeEntryViews(diaryId);
  redirect(`/exchange/${diaryId}?view=latest`);
}

export async function updateExchangeDiaryTitle(
  previousState: ExchangeDiaryTitleActionState,
  formData: FormData,
): Promise<ExchangeDiaryTitleActionState> {
  const diaryId = getUuid(formData, "diaryId");
  const rawTitle = formData.get("title");

  if (!diaryId || typeof rawTitle !== "string") {
    return {
      error: INPUT_ERROR,
      fieldError: null,
      completed: false,
      normalizedTitle: previousState.normalizedTitle,
      revision: previousState.revision + 1,
    };
  }

  const normalizedTitle = rawTitle.trim();

  if (getUnicodeCodePointCount(normalizedTitle) > 120) {
    return {
      error: "入力内容を確認してください。",
      fieldError: "タイトルは120文字以下で入力してください。",
      completed: false,
      normalizedTitle: rawTitle,
      revision: previousState.revision + 1,
    };
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return {
      error: AUTH_ERROR,
      fieldError: null,
      completed: false,
      normalizedTitle: rawTitle,
      revision: previousState.revision + 1,
    };
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_update_exchange_diary_title",
      {
        p_diary_id: diaryId,
        p_title: normalizedTitle === "" ? null : normalizedTitle,
      },
    );
  } catch {
    return {
      error: DIARY_MUTATION_ERROR,
      fieldError: null,
      completed: false,
      normalizedTitle: rawTitle,
      revision: previousState.revision + 1,
    };
  }

  if (
    result.error ||
    typeof result.data !== "string" ||
    result.data.toLowerCase() !== diaryId
  ) {
    return {
      error: DIARY_MUTATION_ERROR,
      fieldError: null,
      completed: false,
      normalizedTitle: rawTitle,
      revision: previousState.revision + 1,
    };
  }

  revalidateExchangeDiaryMutationViews(diaryId);

  return {
    error: null,
    fieldError: null,
    completed: true,
    normalizedTitle,
    revision: previousState.revision + 1,
  };
}

export async function archiveExchangeDiary(
  previousState: ExchangeDiaryMutationActionState,
  formData: FormData,
): Promise<ExchangeDiaryMutationActionState> {
  const diaryId = getUuid(formData, "diaryId");

  if (!diaryId) {
    return diaryMutationErrorState(previousState, INPUT_ERROR);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return diaryMutationErrorState(previousState, AUTH_ERROR);
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_archive_exchange_diary",
      { p_diary_id: diaryId },
    );
  } catch {
    return diaryMutationErrorState(previousState, DIARY_MUTATION_ERROR);
  }

  if (
    result.error ||
    typeof result.data !== "string" ||
    result.data.toLowerCase() !== diaryId
  ) {
    return diaryMutationErrorState(previousState, DIARY_MUTATION_ERROR);
  }

  revalidateExchangeDiaryMutationViews(diaryId);
  redirect(`/exchange/${diaryId}?view=latest`);
}

export async function deleteExchangeEntry(
  previousState: ExchangeDiaryMutationActionState,
  formData: FormData,
): Promise<ExchangeDiaryMutationActionState> {
  const diaryId = getUuid(formData, "diaryId");
  const entryId = getUuid(formData, "entryId");

  if (!diaryId || !entryId) {
    return diaryMutationErrorState(previousState, INPUT_ERROR);
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return diaryMutationErrorState(previousState, AUTH_ERROR);
  }

  if (
    !(await exchangeEntryBelongsToDiary(
      context.supabase,
      diaryId,
      entryId,
    ))
  ) {
    return diaryMutationErrorState(previousState, ENTRY_DELETE_ERROR);
  }

  let result;

  try {
    result = await context.supabase.rpc(
      "my_diary_soft_delete_exchange_entry",
      { p_entry_id: entryId },
    );
  } catch {
    return diaryMutationErrorState(previousState, ENTRY_DELETE_ERROR);
  }

  if (result.error || result.data !== true) {
    return diaryMutationErrorState(previousState, ENTRY_DELETE_ERROR);
  }

  revalidateExchangeDiaryMutationViews(diaryId);
  return diaryMutationCompletedState(previousState);
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
