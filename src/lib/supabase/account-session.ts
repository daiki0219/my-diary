import type { SupabaseClient } from "@supabase/supabase-js";

export const ACCOUNT_UNAVAILABLE_ERROR = "account-unavailable";
export const ACCOUNT_CHECK_FAILED_ERROR = "account-check-failed";

export type AccountSessionState =
  | { kind: "unauthenticated" }
  | { kind: "active"; userId: string }
  | { kind: "non-active"; userId: string }
  | { kind: "account-missing"; userId: string }
  | { kind: "query-error"; userId: string };

export type AuthSessionContext = {
  accountState: AccountSessionState;
  isPasswordRecovery: boolean;
};

export function hasPasswordRecoveryAuthenticationMethod(amr: unknown) {
  if (!Array.isArray(amr)) {
    return false;
  }

  return amr.some((entry) => {
    if (entry === "recovery") {
      return true;
    }

    return (
      typeof entry === "object" &&
      entry !== null &&
      "method" in entry &&
      (entry as { method?: unknown }).method === "recovery"
    );
  });
}

export async function getAuthSessionContext(
  supabase: SupabaseClient,
): Promise<AuthSessionContext> {
  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const claims = claimsResult?.data?.claims;
  const userId = claims?.sub;

  if (
    !claimsResult ||
    claimsResult.error ||
    typeof userId !== "string" ||
    userId.length === 0
  ) {
    return {
      accountState: { kind: "unauthenticated" },
      isPasswordRecovery: false,
    };
  }

  const isPasswordRecovery = hasPasswordRecoveryAuthenticationMethod(
    claims?.amr,
  );

  let accountResult;

  try {
    accountResult = await supabase
      .from("accounts")
      .select("status")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle<{ status: string }>();
  } catch {
    return {
      accountState: { kind: "query-error", userId },
      isPasswordRecovery,
    };
  }

  if (accountResult.error) {
    return {
      accountState: { kind: "query-error", userId },
      isPasswordRecovery,
    };
  }

  if (!accountResult.data) {
    return {
      accountState: { kind: "account-missing", userId },
      isPasswordRecovery,
    };
  }

  const status = (accountResult.data as { status?: unknown }).status;

  if (status === "active") {
    return {
      accountState: { kind: "active", userId },
      isPasswordRecovery,
    };
  }

  if (typeof status !== "string") {
    return {
      accountState: { kind: "query-error", userId },
      isPasswordRecovery,
    };
  }

  return {
    accountState: { kind: "non-active", userId },
    isPasswordRecovery,
  };
}

export async function getAccountSessionState(
  supabase: SupabaseClient,
): Promise<AccountSessionState> {
  const context = await getAuthSessionContext(supabase);

  return context.accountState;
}

export function canUpdatePasswordFromRecovery(
  context: AuthSessionContext,
) {
  return (
    context.isPasswordRecovery &&
    (context.accountState.kind === "active" ||
      context.accountState.kind === "non-active")
  );
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
