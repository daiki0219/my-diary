import { NextResponse } from "next/server";

import {
  canUpdatePasswordFromRecovery,
  endCurrentAuthSession,
  getAccountGateError,
  getAuthSessionContext,
} from "@/lib/supabase/account-session";
import { createClient } from "@/lib/supabase/server";

function hasPasswordRecoveryRedirectType(data: unknown) {
  return (
    typeof data === "object" &&
    data !== null &&
    "redirectType" in data &&
    (data as { redirectType?: unknown }).redirectType === "recovery"
  );
}

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const requestedRecoveryFlow =
    requestUrl.searchParams.get("flow") === "recovery";

  if (code) {
    const supabase = await createClient();
    const { data, error } =
      await supabase.auth.exchangeCodeForSession(code);

    if (!error) {
      const sessionContext = await getAuthSessionContext(supabase);
      const hasRecoveryRedirectType =
        hasPasswordRecoveryRedirectType(data);

      if (
        requestedRecoveryFlow ||
        hasRecoveryRedirectType ||
        sessionContext.isPasswordRecovery
      ) {
        if (
          hasRecoveryRedirectType &&
          canUpdatePasswordFromRecovery(sessionContext)
        ) {
          return NextResponse.redirect(
            new URL("/reset-password", requestUrl.origin),
          );
        }

        await endCurrentAuthSession(supabase);

        return NextResponse.redirect(
          new URL(
            "/reset-password?error=invalid-link",
            requestUrl.origin,
          ),
        );
      }

      const accountState = sessionContext.accountState;

      if (accountState.kind === "active") {
        return NextResponse.redirect(new URL("/home", requestUrl.origin));
      }

      await endCurrentAuthSession(supabase);

      return NextResponse.redirect(
        new URL(
          `/login?error=${getAccountGateError(accountState)}`,
          requestUrl.origin,
        ),
      );
    }
  }

  if (requestedRecoveryFlow) {
    return NextResponse.redirect(
      new URL("/reset-password?error=invalid-link", requestUrl.origin),
    );
  }

  return NextResponse.redirect(
    new URL("/login?error=confirmation-failed", requestUrl.origin),
  );
}
