"use server";

import { revalidatePath } from "next/cache";

import { getViewerTimeZone } from "@/lib/account-data";
import { getViewerExchangeNotificationPreference } from "@/lib/exchange-notification-data";
import { createClient } from "@/lib/supabase/server";
import { isSelectableTimeZone } from "@/lib/timezone";

const SAVE_ERROR = "タイムゾーンを保存できませんでした。";
const EXCHANGE_NOTIFICATION_SAVE_ERROR =
  "交換日記の通知設定を保存できませんでした。時間をおいて、もう一度お試しください。";
const EXCHANGE_NOTIFICATION_UNCERTAIN_ERROR =
  "保存結果を確認できませんでした。現在の設定を再読み込みしました。";
const EXCHANGE_NOTIFICATION_UNCONFIRMED_ERROR =
  "保存結果を確認できませんでした。画面を更新して、現在の設定を確認してください。";
const EXCHANGE_NOTIFICATION_ROLLBACK_CODES = new Set(["22023", "42501"]);

export type TimeZoneActionState = {
  status: "idle" | "success" | "error";
  message: string | null;
  revision: number;
};

export type ExchangeNotificationPreferenceActionState = {
  status: "idle" | "success" | "error";
  message: string | null;
  confirmedNewEntryEnabled: boolean | null;
  revision: number;
};

function parseBooleanFormValue(formData: FormData, fieldName: string) {
  const values = formData.getAll(fieldName);

  if (
    values.length !== 1 ||
    (values[0] !== "true" && values[0] !== "false")
  ) {
    return null;
  }

  return values[0] === "true";
}

function exchangeNotificationPreferenceState(
  previousState: ExchangeNotificationPreferenceActionState,
  status: "success" | "error",
  message: string,
  confirmedNewEntryEnabled: boolean | null,
): ExchangeNotificationPreferenceActionState {
  return {
    status,
    message,
    confirmedNewEntryEnabled,
    revision: previousState.revision + 1,
  };
}

async function reconcileExchangeNotificationPreference(
  previousState: ExchangeNotificationPreferenceActionState,
  supabase: Awaited<ReturnType<typeof createClient>>,
  requestedValue: boolean,
  outcome: "failed" | "uncertain",
) {
  const currentPreference = await getViewerExchangeNotificationPreference(
    supabase,
  );

  if (currentPreference.status !== "found") {
    return exchangeNotificationPreferenceState(
      previousState,
      "error",
      EXCHANGE_NOTIFICATION_UNCONFIRMED_ERROR,
      previousState.confirmedNewEntryEnabled,
    );
  }

  if (
    outcome === "uncertain" &&
    currentPreference.newEntryEnabled === requestedValue
  ) {
    revalidatePath("/settings");

    return exchangeNotificationPreferenceState(
      previousState,
      "success",
      "現在の通知設定を確認しました。",
      currentPreference.newEntryEnabled,
    );
  }

  return exchangeNotificationPreferenceState(
    previousState,
    "error",
    outcome === "failed"
      ? EXCHANGE_NOTIFICATION_SAVE_ERROR
      : EXCHANGE_NOTIFICATION_UNCERTAIN_ERROR,
    currentPreference.newEntryEnabled,
  );
}

export async function updateExchangeNotificationPreference(
  previousState: ExchangeNotificationPreferenceActionState,
  formData: FormData,
): Promise<ExchangeNotificationPreferenceActionState> {
  const newEntryEnabled = parseBooleanFormValue(
    formData,
    "newEntryEnabled",
  );

  if (newEntryEnabled === null) {
    return exchangeNotificationPreferenceState(
      previousState,
      "error",
      EXCHANGE_NOTIFICATION_SAVE_ERROR,
      previousState.confirmedNewEntryEnabled,
    );
  }

  const supabase = await createClient();
  const currentPreference = await getViewerExchangeNotificationPreference(
    supabase,
  );

  if (currentPreference.status !== "found") {
    return exchangeNotificationPreferenceState(
      previousState,
      "error",
      EXCHANGE_NOTIFICATION_SAVE_ERROR,
      previousState.confirmedNewEntryEnabled,
    );
  }

  let result;

  try {
    result = await supabase.rpc(
      "my_diary_update_exchange_notification_preference",
      { p_new_entry_enabled: newEntryEnabled },
    );
  } catch {
    return reconcileExchangeNotificationPreference(
      previousState,
      supabase,
      newEntryEnabled,
      "uncertain",
    );
  }

  if (result.error) {
    return reconcileExchangeNotificationPreference(
      previousState,
      supabase,
      newEntryEnabled,
      EXCHANGE_NOTIFICATION_ROLLBACK_CODES.has(result.error.code)
        ? "failed"
        : "uncertain",
    );
  }

  if (result.data !== true) {
    return reconcileExchangeNotificationPreference(
      previousState,
      supabase,
      newEntryEnabled,
      "uncertain",
    );
  }

  revalidatePath("/settings");

  return {
    status: "success",
    message: "交換日記の通知設定を保存しました。",
    confirmedNewEntryEnabled: newEntryEnabled,
    revision: previousState.revision + 1,
  };
}

export async function updateTimeZone(
  previousState: TimeZoneActionState,
  formData: FormData,
): Promise<TimeZoneActionState> {
  const timezone = formData.get("timezone");
  const supabase = await createClient();
  const viewerResult = await getViewerTimeZone(supabase);

  if (
    viewerResult.error ||
    !isSelectableTimeZone(timezone, viewerResult.timezone)
  ) {
    return {
      status: "error",
      message: SAVE_ERROR,
      revision: previousState.revision + 1,
    };
  }

  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const userId = claimsResult?.data?.claims?.sub;

  if (!claimsResult || claimsResult.error || !userId) {
    return {
      status: "error",
      message: SAVE_ERROR,
      revision: previousState.revision + 1,
    };
  }

  let updateResult;

  try {
    updateResult = await supabase
      .from("accounts")
      .update({ timezone })
      .eq("user_id", userId)
      .select("timezone")
      .limit(1)
      .maybeSingle<{ timezone: string }>();
  } catch {
    return {
      status: "error",
      message: SAVE_ERROR,
      revision: previousState.revision + 1,
    };
  }

  if (
    updateResult.error ||
    !updateResult.data ||
    updateResult.data.timezone !== timezone
  ) {
    return {
      status: "error",
      message: SAVE_ERROR,
      revision: previousState.revision + 1,
    };
  }

  revalidatePath("/settings");

  return {
    status: "success",
    message: "設定を保存しました。",
    revision: previousState.revision + 1,
  };
}
