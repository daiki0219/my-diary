"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import type { AuthActionState } from "@/app/auth/actions";

type AuthFormProps = {
  action: (
    state: AuthActionState,
    formData: FormData,
  ) => Promise<AuthActionState>;
  mode: "login" | "sign-up";
};

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();

  return (
    <button
      className="w-full rounded-control bg-brand-primary px-5 py-3 font-semibold text-white transition hover:bg-brand-primary-hover disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text"
      aria-disabled={pending}
      disabled={pending}
      type="submit"
    >
      {pending ? "送信中…" : label}
    </button>
  );
}

export function AuthForm({ action, mode }: AuthFormProps) {
  const [state, formAction] = useActionState(
    action,
    { error: null },
  );
  const isLogin = mode === "login";

  return (
    <form action={formAction} className="mt-8 space-y-5">
      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor={`${mode}-email`}
        >
          メールアドレス
        </label>
        <input
          autoComplete="email"
          className="w-full rounded-control border border-border-control bg-surface px-4 py-3 text-base text-text-primary transition placeholder:text-text-muted focus:border-focus"
          id={`${mode}-email`}
          inputMode="email"
          name="email"
          placeholder="name@example.com"
          required
          type="email"
        />
      </div>

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor={`${mode}-password`}
        >
          パスワード
        </label>
        <input
          autoComplete={isLogin ? "current-password" : "new-password"}
          className="w-full rounded-control border border-border-control bg-surface px-4 py-3 text-base text-text-primary transition placeholder:text-text-muted focus:border-focus"
          id={`${mode}-password`}
          minLength={6}
          name="password"
          required
          type="password"
        />
        {isLogin && (
          <p className="mt-2 text-right text-sm">
            <Link
              className="font-semibold text-orange-700 underline-offset-4 hover:underline focus-visible:rounded-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/forgot-password"
            >
              パスワードを忘れた方
            </Link>
          </p>
        )}
        {!isLogin && (
          <p className="mt-2 text-xs leading-5 text-stone-500">
            6文字以上で設定してください。
          </p>
        )}
      </div>

      {state.error && (
        <p
          aria-live="polite"
          className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          {state.error}
        </p>
      )}

      <SubmitButton label={isLogin ? "ログイン" : "新規登録"} />

      <p className="text-center text-sm text-stone-600">
        {isLogin ? "アカウントをお持ちでない方は" : "すでに登録済みの方は"}
        <Link
          className="ml-1 font-semibold text-orange-700 underline-offset-4 hover:underline"
          href={isLogin ? "/sign-up" : "/login"}
        >
          {isLogin ? "新規登録" : "ログイン"}
        </Link>
      </p>
    </form>
  );
}
