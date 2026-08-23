"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import type { PasswordUpdateActionState } from "@/app/auth/actions";
import { Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormInput } from "@/components/ui/form-controls";
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
    <Button
      aria-disabled={pending}
      className="w-full"
      disabled={pending}
      type="submit"
      variant="primary"
    >
      {pending ? "更新中…" : "新しいパスワードを設定"}
    </Button>
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
          className="mb-2 block text-sm font-medium text-text-secondary"
          htmlFor="reset-password"
        >
          新しいパスワード
        </label>
        <FormInput
          aria-describedby={passwordDescriptionId}
          aria-invalid={state.passwordInvalid}
          autoComplete="new-password"
          id="reset-password"
          minLength={PASSWORD_MIN_LENGTH}
          name="password"
          required
          type="password"
        />
        <p
          className="mt-2 text-xs leading-5 text-text-muted"
          id="reset-password-requirements"
        >
          {PASSWORD_REQUIREMENTS_MESSAGE}
        </p>
      </div>

      <div>
        <label
          className="mb-2 block text-sm font-medium text-text-secondary"
          htmlFor="reset-password-confirmation"
        >
          新しいパスワード（確認）
        </label>
        <FormInput
          aria-describedby={confirmationDescriptionId}
          aria-invalid={state.confirmationInvalid}
          autoComplete="new-password"
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
