import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { requestPasswordReset } from "@/app/auth/actions";
import { PasswordResetRequestForm } from "@/components/auth/password-reset-request-form";
import { Surface } from "@/components/ui/surface";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "パスワード再設定",
};

export default async function ForgotPasswordPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (data?.claims) {
    redirect("/home");
  }

  return (
    <section className="flex flex-1 items-center px-5 py-10 sm:px-8">
      <Surface className="mx-auto w-full max-w-md p-6 sm:p-8" variant="elevated">
        <p className="text-sm font-medium text-brand-primary-hover">
          ログインでお困りの方へ
        </p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight text-text-primary">
          パスワード再設定
        </h1>
        <p className="mt-3 break-words text-sm leading-6 text-text-secondary">
          登録したメールアドレスへ、新しいパスワードを設定するための案内を送信します。
        </p>

        <PasswordResetRequestForm action={requestPasswordReset} />
      </Surface>
    </section>
  );
}
