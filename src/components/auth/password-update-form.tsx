"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import type { PasswordUpdateActionState } from "@/app/auth/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import {
  PASSWORD_MIN_LENGTH,
  PASSWORD_REQUIREMENTS_MESSAGE,
} from "@/lib/auth-validation";

type PasswordUpdateFormProps = {
  action: (
    state: PasswordUpdateActionState,
    formData: FormData,
  ) => Promise<PasswordUpdateActionState>;
};

const initialState: PasswordUpdateActionState = {
  confirmationInvalid: false,
  error: null,
  passwordInvalid: false,
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
      {pending ? "更新中…" : "新しいパスワードを設定"}
    </button>
  );
}

export function PasswordUpdateForm({ action }: PasswordUpdateFormProps) {
  const [state, formAction] = useActionState(action, initialState);
  const passwordDescriptionId = state.passwordInvalid
    ? "reset-password-error"
    : "reset-password-requirements";
  const confirmationDescriptionId = state.confirmationInvalid
    ? "reset-password-error"
    : undefined;

  return (
    <form action={formAction} className="mt-8 space-y-5" noValidate>
      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="reset-password"
        >
          新しいパスワード
        </label>
        <input
          aria-describedby={passwordDescriptionId}
          aria-invalid={state.passwordInvalid}
          autoComplete="new-password"
          className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 aria-[invalid=true]:border-red-400 aria-[invalid=true]:focus:border-red-500 aria-[invalid=true]:focus:ring-red-100"
          id="reset-password"
          minLength={PASSWORD_MIN_LENGTH}
          name="password"
          required
          type="password"
        />
        <p
          className="mt-2 text-xs leading-5 text-stone-500"
          id="reset-password-requirements"
        >
          {PASSWORD_REQUIREMENTS_MESSAGE}
        </p>
      </div>

      <div>
        <label
          className="mb-2 block text-sm font-medium text-stone-700"
          htmlFor="reset-password-confirmation"
        >
          新しいパスワード（確認）
        </label>
        <input
          aria-describedby={confirmationDescriptionId}
          aria-invalid={state.confirmationInvalid}
          autoComplete="new-password"
          className="w-full rounded-2xl border border-stone-300 bg-white px-4 py-3 text-base outline-none transition focus:border-orange-500 focus:ring-2 focus:ring-orange-100 aria-[invalid=true]:border-red-400 aria-[invalid=true]:focus:border-red-500 aria-[invalid=true]:focus:ring-red-100"
          id="reset-password-confirmation"
          minLength={PASSWORD_MIN_LENGTH}
          name="passwordConfirmation"
          required
          type="password"
        />
      </div>

      {state.error && (
        <FeedbackPanel
          id="reset-password-error"
          role="alert"
          variant="error"
        >
          {state.error}
        </FeedbackPanel>
      )}

      <SubmitButton />
    </form>
  );
}
