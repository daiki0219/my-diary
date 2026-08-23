import type { Metadata } from "next";

import { updatePasswordFromRecovery } from "@/app/auth/actions";
import { PasswordUpdateForm } from "@/components/auth/password-update-form";
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { Surface } from "@/components/ui/surface";
import {
  canUpdatePasswordFromRecovery,
  getAuthSessionContext,
} from "@/lib/supabase/account-session";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "新しいパスワードを設定",
};

export default async function ResetPasswordPage() {
  const supabase = await createClient();
  const recoveryContext = await getAuthSessionContext(supabase);
  const canUpdatePassword = canUpdatePasswordFromRecovery(recoveryContext);

  return (
    <section className="flex flex-1 items-center px-5 py-10 sm:px-8">
      <Surface className="mx-auto w-full max-w-md p-6 sm:p-8" variant="elevated">
        <p className="text-sm font-medium text-brand-primary-hover">
          アカウントを安全に復旧
        </p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight text-text-primary">
          新しいパスワードを設定
        </h1>

        {canUpdatePassword ? (
          <>
            <p className="mt-3 break-words text-sm leading-6 text-text-secondary">
              これから使う新しいパスワードを入力してください。更新後は、ログイン画面から新しいパスワードでログインします。
            </p>
            <PasswordUpdateForm action={updatePasswordFromRecovery} />
          </>
        ) : (
          <div className="mt-6 space-y-5">
            <FeedbackPanel role="alert" variant="error">
              パスワード再設定のリンクを確認できませんでした。リンクの期限が切れているか、すでに使用されている可能性があります。
            </FeedbackPanel>
            <div className="flex flex-col gap-3 sm:flex-row">
              <ActionLink
                className="w-full sm:flex-1"
                href="/forgot-password"
                variant="primary"
              >
                もう一度申し込む
              </ActionLink>
              <ActionLink
                className="w-full sm:flex-1"
                href="/login"
                variant="neutral"
              >
                ログインへ戻る
              </ActionLink>
            </div>
          </div>
        )}
      </Surface>
    </section>
  );
}
