import { NextResponse } from "next/server";

import {
  endCurrentAuthSession,
  getAccountGateError,
  getAccountSessionState,
} from "@/lib/supabase/account-session";
import { createClient } from "@/lib/supabase/server";

function getSafeNextPath(value: string | null) {
  if (value?.startsWith("/") && !value.startsWith("//")) {
    return value;
  }

  return "/home";
}

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const nextPath = getSafeNextPath(requestUrl.searchParams.get("next"));

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (!error) {
      const accountState = await getAccountSessionState(supabase);

      if (accountState.kind === "active") {
        return NextResponse.redirect(new URL(nextPath, requestUrl.origin));
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

  return NextResponse.redirect(
    new URL("/login?error=confirmation-failed", requestUrl.origin),
  );
}
