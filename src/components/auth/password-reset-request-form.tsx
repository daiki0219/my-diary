"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";

import type { PasswordResetRequestActionState } from "@/app/auth/actions";
import { ActionLink, Button } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { FormInput } from "@/components/ui/form-controls";

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
    <Button
      aria-disabled={pending}
      className="w-full"
      disabled={pending}
      type="submit"
      variant="primary"
    >
      {pending ? "送信中…" : "再設定メールを送信"}
    </Button>
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
          className="mb-2 block text-sm font-medium text-text-secondary"
          htmlFor="forgot-password-email"
        >
          メールアドレス
        </label>
        <FormInput
          aria-describedby={emailDescriptionId}
          aria-invalid={state.emailInvalid}
          autoComplete="email"
          id="forgot-password-email"
          inputMode="email"
          name="email"
          placeholder="name@example.com"
          required
          type="email"
        />
        <p
          className="mt-2 text-xs leading-5 text-text-muted"
          id="forgot-password-email-help"
        >
          登録に使ったメールアドレスを入力してください。
        </p>
      </div>

      {state.error && (
        <FeedbackPanel
          id="forgot-password-email-error"
          role="alert"
          variant="error"
        >
          {state.error}
        </FeedbackPanel>
      )}

      {state.success && (
        <FeedbackPanel role="status" variant="success">
          入力されたメールアドレスが登録されている場合、パスワード再設定の案内を送信します。
        </FeedbackPanel>
      )}

      <SubmitButton />

      <div className="border-t border-border-subtle pt-4">
        <ActionLink
          className="w-full"
          href="/login"
          variant="quiet"
        >
          ログインへ戻る
        </ActionLink>
      </div>
    </form>
  );
}
