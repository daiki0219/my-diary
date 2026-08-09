"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import type { PasswordResetRequestActionState } from "@/app/auth/actions";

type PasswordResetRequestFormProps = {
  action: (
    state: PasswordResetRequestActionState,
    formData: FormData,
  ) => Promise<PasswordResetRequestActionState>;
};

const initialState: PasswordResetRequestActionState = {
  emailInvalid: false,
  error: null,
  success: false,
};

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      aria-disabled={pending}
      className="w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-wait disabled:bg-stone-400"
      disabled={pending}
      type="submit"
    >
      {pending ? "送信中…" : "再設定メールを送信"}
    </button>
  );
}

export function PasswordResetRequestForm({
  action,
}: PasswordResetRequestFormProps) {
  const [state, formAction] = useActionState(action, initialState);
  const emailDescriptionId = state.emailInvalid
    ? "forgot-password-email-error"
    : "forgot-password-email-help";

  return (
    <form action={formAction} className="mt-8 space-y-5" noValidate>
      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="forgot-password-email"
        >
          メールアドレス
        </label>
        <input
          aria-describedby={emailDescriptionId}
          aria-invalid={state.emailInvalid}
          autoComplete="email"
          className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition placeholder:text-stone-400 focus:border-orange-500 focus:ring-2 focus:ring-orange-100 aria-[invalid=true]:border-red-400 aria-[invalid=true]:focus:border-red-500 aria-[invalid=true]:focus:ring-red-100"
          id="forgot-password-email"
          inputMode="email"
          name="email"
          placeholder="name@example.com"
          required
          type="email"
        />
        <p
          className="mt-2 text-xs leading-5 text-stone-500"
          id="forgot-password-email-help"
        >
          登録に使ったメールアドレスを入力してください。
        </p>
      </div>

      {state.error && (
        <p
          className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          id="forgot-password-email-error"
          role="alert"
        >
          {state.error}
        </p>
      )}

      {state.success && (
        <p
          className="rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm leading-6 text-green-800"
          role="status"
        >
          入力されたメールアドレスが登録されている場合、パスワード再設定の案内を送信します。
        </p>
      )}

      <SubmitButton />

      <p className="text-center text-sm text-stone-600">
        <Link
          className="font-semibold text-orange-700 underline-offset-4 hover:underline focus-visible:rounded-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
          href="/login"
        >
          ログインへ戻る
        </Link>
      </p>
    </form>
  );
}
