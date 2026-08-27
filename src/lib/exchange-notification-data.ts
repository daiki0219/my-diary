import type { SupabaseClient } from "@supabase/supabase-js";

import { getAccountSessionState } from "@/lib/supabase/account-session";

export type ViewerExchangeNotificationPreferenceResult =
  | { status: "found"; newEntryEnabled: boolean; updatedAt: string }
  | { status: "unauthenticated" | "unavailable" };

export async function getViewerExchangeNotificationPreference(
  supabase: SupabaseClient,
): Promise<ViewerExchangeNotificationPreferenceResult> {
  const sessionState = await getAccountSessionState(supabase);

  if (sessionState.kind === "unauthenticated") {
    return { status: "unauthenticated" };
  }

  if (sessionState.kind !== "active") {
    return { status: "unavailable" };
  }

  try {
    const result = await supabase
      .from("exchange_notification_preferences")
      .select("new_entry_enabled, updated_at")
      .eq("user_id", sessionState.userId)
      .limit(2)
      .returns<unknown[]>();

    if (result.error || result.data?.length !== 1) {
      return { status: "unavailable" };
    }

    const row = result.data[0];

    if (
      typeof row !== "object" ||
      row === null ||
      !("new_entry_enabled" in row) ||
      typeof row.new_entry_enabled !== "boolean" ||
      !("updated_at" in row) ||
      typeof row.updated_at !== "string" ||
      !Number.isFinite(Date.parse(row.updated_at))
    ) {
      return { status: "unavailable" };
    }

    return {
      status: "found",
      newEntryEnabled: row.new_entry_enabled,
      updatedAt: row.updated_at,
    };
  } catch {
    return { status: "unavailable" };
  }
}
