import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { isUuid } from "@/lib/profile-data";
import { hasPasswordRecoveryAuthenticationMethod } from "@/lib/supabase/account-session";

export type AdminSessionState =
  | { kind: "active-admin"; userId: string }
  | { kind: "unauthenticated" }
  | { kind: "denied" }
  | { kind: "account-missing" }
  | { kind: "query-error" };

type AdminAccountClassification = "active-admin" | "denied" | "invalid";

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

export function classifyAdminAccountRow(
  value: unknown,
): AdminAccountClassification {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, ["role", "status"]) ||
    !("role" in value) ||
    !("status" in value) ||
    (value.role !== "user" && value.role !== "admin") ||
    (value.status !== "active" &&
      value.status !== "suspended" &&
      value.status !== "deactivated")
  ) {
    return "invalid";
  }

  return value.role === "admin" && value.status === "active"
    ? "active-admin"
    : "denied";
}

export async function getAdminSessionState(
  supabase: SupabaseClient,
): Promise<AdminSessionState> {
  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const claims = claimsResult?.data?.claims;
  const userId = claims?.sub;

  if (
    !claimsResult ||
    claimsResult.error ||
    typeof userId !== "string" ||
    !isUuid(userId)
  ) {
    return { kind: "unauthenticated" };
  }

  if (hasPasswordRecoveryAuthenticationMethod(claims?.amr)) {
    return { kind: "denied" };
  }

  const canonicalUserId = userId.toLowerCase();
  let accountResult;

  try {
    accountResult = await supabase
      .from("accounts")
      .select("role, status")
      .eq("user_id", canonicalUserId)
      .limit(2)
      .returns<unknown[]>();
  } catch {
    return { kind: "query-error" };
  }

  if (accountResult.error || !Array.isArray(accountResult.data)) {
    return { kind: "query-error" };
  }

  if (accountResult.data.length === 0) {
    return { kind: "account-missing" };
  }

  if (accountResult.data.length !== 1) {
    return { kind: "query-error" };
  }

  const classification = classifyAdminAccountRow(accountResult.data[0]);

  if (classification === "invalid") {
    return { kind: "query-error" };
  }

  return classification === "active-admin"
    ? { kind: "active-admin", userId: canonicalUserId }
    : { kind: "denied" };
}
