import type { SupabaseClient } from "@supabase/supabase-js";

import { getAccountSessionState } from "@/lib/supabase/account-session";
import { isRuntimeTimeZone } from "@/lib/timezone";

export type ViewerTimeZoneResult =
  | { timezone: string; error: null }
  | {
      timezone: null;
      error:
        | "unauthenticated"
        | "account-unavailable"
        | "query-error"
        | "invalid-timezone";
    };

export async function getViewerTimeZone(
  supabase: SupabaseClient,
): Promise<ViewerTimeZoneResult> {
  const sessionState = await getAccountSessionState(supabase);

  if (sessionState.kind === "unauthenticated") {
    return { timezone: null, error: "unauthenticated" };
  }

  if (
    sessionState.kind === "non-active" ||
    sessionState.kind === "account-missing"
  ) {
    return { timezone: null, error: "account-unavailable" };
  }

  if (sessionState.kind === "query-error") {
    return { timezone: null, error: "query-error" };
  }

  let result;

  try {
    result = await supabase
      .from("accounts")
      .select("timezone")
      .eq("user_id", sessionState.userId)
      .limit(1)
      .maybeSingle<{ timezone: unknown }>();
  } catch {
    return { timezone: null, error: "query-error" };
  }

  if (result.error || !result.data) {
    return { timezone: null, error: "query-error" };
  }

  if (!isRuntimeTimeZone(result.data.timezone)) {
    return { timezone: null, error: "invalid-timezone" };
  }

  return { timezone: result.data.timezone, error: null };
}
