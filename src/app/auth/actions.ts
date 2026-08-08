"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import {
  endCurrentAuthSession,
  getAccountSessionState,
} from "@/lib/supabase/account-session";
import { createClient } from "@/lib/supabase/server";

export type AuthActionState = {
  error: string | null;
};

function getCredentials(formData: FormData) {
  const email = formData.get("email");
  const password = formData.get("password");

  if (typeof email !== "string" || typeof password !== "string") {
    return null;
  }

  const normalizedEmail = email.trim();

  if (!normalizedEmail || !normalizedEmail.includes("@")) {
    return null;
  }

  return { email: normalizedEmail, password };
}

function getAuthErrorMessage(code?: string) {
  switch (code) {
    case "invalid_credentials":
      return "メールアドレスまたはパスワードが正しくありません。";
    case "email_not_confirmed":
      return "メールアドレスの確認が完了していません。確認メールをご確認ください。";
    case "user_already_exists":
      return "このメールアドレスはすでに登録されています。";
    case "weak_password":
      return "パスワードが要件を満たしていません。より長く安全なパスワードを設定してください。";
    case "signup_disabled":
      return "現在、新規登録を受け付けていません。";
    case "over_email_send_rate_limit":
    case "over_request_rate_limit":
      return "短時間に多くの操作が行われました。しばらく待ってからお試しください。";
    default:
      return "認証処理に失敗しました。時間をおいてもう一度お試しください。";
  }
}

async function getEmailRedirectTo() {
  const requestHeaders = await headers();
  const candidate =
    process.env.NEXT_PUBLIC_SITE_URL || requestHeaders.get("origin");

  if (!candidate) {
    return undefined;
  }

  try {
    const siteUrl = new URL(candidate);

    if (siteUrl.protocol !== "http:" && siteUrl.protocol !== "https:") {
      return undefined;
    }

    return new URL("/auth/callback", siteUrl).toString();
  } catch {
    return undefined;
  }
}

export async function login(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const credentials = getCredentials(formData);

  if (!credentials) {
    return { error: "メールアドレスとパスワードを入力してください。" };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(credentials);

  if (error) {
    return { error: getAuthErrorMessage(error.code) };
  }

  const accountState = await getAccountSessionState(supabase);

  if (accountState.kind !== "active") {
    await endCurrentAuthSession(supabase);

    return {
      error:
        accountState.kind === "non-active" ||
        accountState.kind === "account-missing"
          ? "このアカウントは現在利用できません。"
          : "ログイン状態を安全に確認できませんでした。時間をおいてもう一度お試しください。",
    };
  }

  redirect("/home");
}

export async function signUp(
  _previousState: AuthActionState,
  formData: FormData,
): Promise<AuthActionState> {
  const credentials = getCredentials(formData);

  if (!credentials) {
    return { error: "有効なメールアドレスとパスワードを入力してください。" };
  }

  if (credentials.password.length < 6) {
    return { error: "パスワードは6文字以上で入力してください。" };
  }

  const emailRedirectTo = await getEmailRedirectTo();
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    ...credentials,
    ...(emailRedirectTo
      ? {
          options: {
            emailRedirectTo,
          },
        }
      : {}),
  });

  if (error) {
    return { error: getAuthErrorMessage(error.code) };
  }

  if (data.session) {
    const accountState = await getAccountSessionState(supabase);

    if (accountState.kind !== "active") {
      await endCurrentAuthSession(supabase);

      return {
        error:
          accountState.kind === "non-active" ||
          accountState.kind === "account-missing"
            ? "このアカウントは現在利用できません。"
            : "登録後のログイン状態を安全に確認できませんでした。時間をおいてもう一度お試しください。",
      };
    }

    redirect("/home");
  }

  redirect("/sign-up?status=check-email");
}

export async function logout() {
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut();

  if (error) {
    redirect("/home?error=logout-failed");
  }

  redirect("/login?status=signed-out");
}
