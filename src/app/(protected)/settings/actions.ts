"use server";

import { revalidatePath } from "next/cache";

import { getViewerTimeZone } from "@/lib/account-data";
import { createClient } from "@/lib/supabase/server";
import { isSelectableTimeZone } from "@/lib/timezone";

const SAVE_ERROR = "タイムゾーンを保存できませんでした。";

export type TimeZoneActionState = {
  status: "idle" | "success" | "error";
  message: string | null;
  revision: number;
};

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
