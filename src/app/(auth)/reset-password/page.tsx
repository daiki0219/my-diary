import type { Metadata } from "next";
import Link from "next/link";

import { updatePasswordFromRecovery } from "@/app/auth/actions";
import { PasswordUpdateForm } from "@/components/auth/password-update-form";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
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
      <div className="mx-auto min-w-0 w-full max-w-md rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8">
        <p className="text-sm font-medium text-orange-700">
          アカウントを安全に復旧
        </p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
          新しいパスワードを設定
        </h1>

        {canUpdatePassword ? (
          <>
            <p className="mt-3 break-words text-sm leading-6 text-stone-600">
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
              <Link
                className="rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                href="/forgot-password"
              >
                もう一度申し込む
              </Link>
              <Link
                className="rounded-full border border-stone-300 px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
                href="/login"
              >
                ログインへ戻る
              </Link>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
