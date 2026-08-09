"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";

import {
  getPasswordValidationError,
} from "@/lib/auth-validation";
import {
  canUpdatePasswordFromRecovery,
  endCurrentAuthSession,
  getAccountSessionState,
  getAuthSessionContext,
} from "@/lib/supabase/account-session";
import { createClient } from "@/lib/supabase/server";

export type AuthActionState = {
  error: string | null;
};

export type PasswordResetRequestActionState = {
  emailInvalid: boolean;
  error: string | null;
  success: boolean;
};

export type PasswordUpdateActionState = {
  confirmationInvalid: boolean;
  error: string | null;
  passwordInvalid: boolean;
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

function getHttpOrigin(candidate: string | null) {
  if (!candidate) {
    return null;
  }

  try {
    const url = new URL(candidate);

    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }

    return url.origin;
  } catch {
    return null;
  }
}

function getFirstHeaderValue(value: string | null) {
  return value?.split(",", 1)[0]?.trim() || null;
}

async function getTrustedSiteOrigin() {
  const configuredOrigin = getHttpOrigin(
    process.env.NEXT_PUBLIC_SITE_URL ?? null,
  );

  if (configuredOrigin) {
    return configuredOrigin;
  }

  const requestHeaders = await headers();
  const requestOrigin = getHttpOrigin(requestHeaders.get("origin"));

  if (!requestOrigin) {
    return undefined;
  }

  const originUrl = new URL(requestOrigin);
  const expectedHost =
    getFirstHeaderValue(requestHeaders.get("x-forwarded-host")) ??
    requestHeaders.get("host");
  const expectedProtocol = getFirstHeaderValue(
    requestHeaders.get("x-forwarded-proto"),
  );

  if (expectedHost && originUrl.host !== expectedHost) {
    return undefined;
  }

  if (
    expectedProtocol &&
    originUrl.protocol !== `${expectedProtocol.toLowerCase()}:`
  ) {
    return undefined;
  }

  return requestOrigin;
}

async function getEmailRedirectTo(flow?: "recovery") {
  const siteOrigin = await getTrustedSiteOrigin();

  if (!siteOrigin) {
    return undefined;
  }

  const callbackUrl = new URL("/auth/callback", siteOrigin);

  if (flow === "recovery") {
    callbackUrl.searchParams.set("flow", "recovery");
  }

  return callbackUrl.toString();
}

function getPasswordResetRequestEmail(formData: FormData) {
  const value = formData.get("email");

  if (typeof value !== "string") {
    return null;
  }

  const email = value.trim();

  if (
    !email ||
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+$/.test(email)
  ) {
    return null;
  }

  return email;
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

  const passwordError = getPasswordValidationError(credentials.password);

  if (passwordError) {
    return { error: passwordError };
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

export async function requestPasswordReset(
  _previousState: PasswordResetRequestActionState,
  formData: FormData,
): Promise<PasswordResetRequestActionState> {
  const email = getPasswordResetRequestEmail(formData);

  if (!email) {
    return {
      emailInvalid: true,
      error: "有効なメールアドレスを入力してください。",
      success: false,
    };
  }

  const redirectTo = await getEmailRedirectTo("recovery");

  if (!redirectTo) {
    return {
      emailInvalid: false,
      error:
        "パスワード再設定の案内を送信できませんでした。時間をおいてもう一度お試しください。",
      success: false,
    };
  }

  try {
    const supabase = await createClient();
    await supabase.auth.resetPasswordForEmail(email, { redirectTo });
  } catch {
    return {
      emailInvalid: false,
      error:
        "パスワード再設定の案内を送信できませんでした。時間をおいてもう一度お試しください。",
      success: false,
    };
  }

  return {
    emailInvalid: false,
    error: null,
    success: true,
  };
}

export async function updatePasswordFromRecovery(
  _previousState: PasswordUpdateActionState,
  formData: FormData,
): Promise<PasswordUpdateActionState> {
  const password = formData.get("password");
  const confirmation = formData.get("passwordConfirmation");

  if (typeof password !== "string") {
    return {
      confirmationInvalid: false,
      error: "新しいパスワードを入力してください。",
      passwordInvalid: true,
    };
  }

  const passwordError = getPasswordValidationError(password);

  if (passwordError) {
    return {
      confirmationInvalid: false,
      error: passwordError,
      passwordInvalid: true,
    };
  }

  if (typeof confirmation !== "string" || confirmation !== password) {
    return {
      confirmationInvalid: true,
      error: "確認用パスワードが一致しません。",
      passwordInvalid: false,
    };
  }

  const supabase = await createClient();
  const recoveryContext = await getAuthSessionContext(supabase);

  if (!canUpdatePasswordFromRecovery(recoveryContext)) {
    return {
      confirmationInvalid: false,
      error:
        "パスワード再設定を確認できませんでした。もう一度再設定を申し込んでください。",
      passwordInvalid: false,
    };
  }

  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    return {
      confirmationInvalid: false,
      error:
        "パスワードを更新できませんでした。もう一度再設定を申し込んでください。",
      passwordInvalid: false,
    };
  }

  await endCurrentAuthSession(supabase);
  redirect("/login?status=password-reset");
}

export async function logout() {
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut();

  if (error) {
    redirect("/home?error=logout-failed");
  }

  redirect("/login?status=signed-out");
}
