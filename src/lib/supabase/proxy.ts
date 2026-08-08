import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import {
  ACCOUNT_CHECK_FAILED_ERROR,
  endCurrentAuthSession,
  getAccountGateError,
  getAccountSessionState,
} from "./account-session";
import { getSupabaseConfig } from "./env";

const publicPathsWithoutSessionGate = new Set([
  "/",
  "/auth/callback",
  "/api/health/supabase",
]);

function shouldCheckAccountStatus(pathname: string) {
  return !publicPathsWithoutSessionGate.has(pathname);
}

function copyResponseCookies(source: NextResponse, target: NextResponse) {
  source.cookies.getAll().forEach((cookie) => {
    target.cookies.set(cookie);
  });

  return target;
}

function isPostImagePath(pathname: string) {
  return pathname.startsWith("/post-images/");
}

function isServerActionRequest(request: NextRequest) {
  return request.headers.has("next-action");
}

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { url, publishableKey } = getSupabaseConfig();

  const supabase = createServerClient(url, publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet, headers) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });

        response = NextResponse.next({ request });

        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });

        Object.entries(headers).forEach(([name, value]) => {
          response.headers.set(name, value);
        });
      },
    },
  });

  if (!shouldCheckAccountStatus(request.nextUrl.pathname)) {
    await supabase.auth.getClaims();
    return response;
  }

  const accountState = await getAccountSessionState(supabase);

  if (
    accountState.kind === "active" ||
    accountState.kind === "unauthenticated"
  ) {
    return response;
  }

  await endCurrentAuthSession(supabase);

  if (isPostImagePath(request.nextUrl.pathname)) {
    return copyResponseCookies(
      response,
      new NextResponse(null, {
        headers: {
          "Cache-Control": "private, no-store, max-age=0",
          "Cross-Origin-Resource-Policy": "same-origin",
          "Referrer-Policy": "no-referrer",
          Vary: "Cookie",
          "X-Content-Type-Options": "nosniff",
        },
        status: 404,
      }),
    );
  }

  const errorCode = getAccountGateError(accountState);
  const loginUrl = new URL("/login", request.url);
  loginUrl.searchParams.set("error", errorCode);

  if (
    request.nextUrl.pathname === "/login" &&
    request.nextUrl.searchParams.get("error") === errorCode
  ) {
    return response;
  }

  if (isServerActionRequest(request)) {
    const actionRedirectResponse = new NextResponse(null, {
      headers: {
        "Cache-Control": "private, no-store, max-age=0",
        "x-action-redirect": `${loginUrl.pathname}${loginUrl.search};replace`,
      },
      status: 200,
    });

    if (errorCode === ACCOUNT_CHECK_FAILED_ERROR) {
      actionRedirectResponse.headers.set("Retry-After", "5");
    }

    return copyResponseCookies(response, actionRedirectResponse);
  }

  const redirectResponse = NextResponse.redirect(
    loginUrl,
    request.method === "GET" || request.method === "HEAD" ? 307 : 303,
  );
  redirectResponse.headers.set("Cache-Control", "private, no-store, max-age=0");

  if (errorCode === ACCOUNT_CHECK_FAILED_ERROR) {
    redirectResponse.headers.set("Retry-After", "5");
  }

  return copyResponseCookies(response, redirectResponse);
}
