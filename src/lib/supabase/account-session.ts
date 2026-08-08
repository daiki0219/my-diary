import type { SupabaseClient } from "@supabase/supabase-js";

export const ACCOUNT_UNAVAILABLE_ERROR = "account-unavailable";
export const ACCOUNT_CHECK_FAILED_ERROR = "account-check-failed";

export type AccountSessionState =
  | { kind: "unauthenticated" }
  | { kind: "active"; userId: string }
  | { kind: "non-active"; userId: string }
  | { kind: "account-missing"; userId: string }
  | { kind: "query-error"; userId: string };

export async function getAccountSessionState(
  supabase: SupabaseClient,
): Promise<AccountSessionState> {
  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const userId = claimsResult?.data?.claims?.sub;

  if (
    !claimsResult ||
    claimsResult.error ||
    typeof userId !== "string" ||
    userId.length === 0
  ) {
    return { kind: "unauthenticated" };
  }

  let accountResult;

  try {
    accountResult = await supabase
      .from("accounts")
      .select("status")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle<{ status: string }>();
  } catch {
    return { kind: "query-error", userId };
  }

  if (accountResult.error) {
    return { kind: "query-error", userId };
  }

  if (!accountResult.data) {
    return { kind: "account-missing", userId };
  }

  const status = (accountResult.data as { status?: unknown }).status;

  if (status === "active") {
    return { kind: "active", userId };
  }

  if (typeof status !== "string") {
    return { kind: "query-error", userId };
  }

  return { kind: "non-active", userId };
}

export async function endCurrentAuthSession(supabase: SupabaseClient) {
  try {
    await supabase.auth.signOut({ scope: "local" });
  } catch {
    // signOutは通常、Auth APIが失敗してもlocal sessionを除去する。
    // 例外時も呼び出し元は通常データへ進ませずfail-closedにする。
  }
}

export function getAccountGateError(
  state: Exclude<AccountSessionState, { kind: "active" }>,
) {
  return state.kind === "non-active" || state.kind === "account-missing"
    ? ACCOUNT_UNAVAILABLE_ERROR
    : ACCOUNT_CHECK_FAILED_ERROR;
}
