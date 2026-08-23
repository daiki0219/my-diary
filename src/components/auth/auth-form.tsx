"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import type { AuthActionState } from "@/app/auth/actions";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormInput } from "@/components/ui/form-controls";

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
    <Button
      className="w-full"
      aria-disabled={pending}
      disabled={pending}
      type="submit"
      variant="primary"
    >
      {pending ? "送信中…" : label}
    </Button>
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
          className="mb-2 block text-sm font-medium text-text-secondary"
          htmlFor={`${mode}-email`}
        >
          メールアドレス
        </label>
        <FormInput
          autoComplete="email"
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
          className="mb-2 block text-sm font-medium text-text-secondary"
          htmlFor={`${mode}-password`}
        >
          パスワード
        </label>
        <FormInput
          aria-describedby={isLogin ? undefined : "sign-up-password-help"}
          autoComplete={isLogin ? "current-password" : "new-password"}
          id={`${mode}-password`}
          minLength={6}
          name="password"
          required
          type="password"
        />
        {isLogin && (
          <p className="mt-2 text-right text-sm">
            <Link
              className="font-semibold text-brand-primary-hover underline-offset-4 hover:underline focus-visible:rounded-sm"
              href="/forgot-password"
            >
              パスワードを忘れた方
            </Link>
          </p>
        )}
        {!isLogin && (
          <p
            className="mt-2 text-xs leading-5 text-text-muted"
            id="sign-up-password-help"
          >
            6文字以上で設定してください。
          </p>
        )}
      </div>

      {state.error && (
        <FeedbackPanel
          aria-live="polite"
          role="alert"
          variant="error"
        >
          {state.error}
        </FeedbackPanel>
      )}

      <SubmitButton label={isLogin ? "ログイン" : "新規登録"} />

      <div className="border-t border-border-subtle pt-4">
        <p className="text-center text-sm text-text-secondary">
          {isLogin ? "アカウントをお持ちでない方は" : "すでに登録済みの方は"}
          <Link
            className="ml-1 font-semibold text-brand-primary-hover underline-offset-4 hover:underline focus-visible:rounded-sm"
            href={isLogin ? "/sign-up" : "/login"}
          >
            {isLogin ? "新規登録" : "ログイン"}
          </Link>
        </p>
      </div>
    </form>
  );
}
