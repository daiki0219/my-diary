import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { signUp } from "@/app/auth/actions";
import { AuthForm } from "@/components/auth/auth-form";
import { ActionLink } from "@/components/ui/actions";
import { Surface } from "@/components/ui/surface";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "新規登録",
};

type SignUpPageProps = {
  searchParams: Promise<{
    status?: string;
  }>;
};

export default async function SignUpPage({ searchParams }: SignUpPageProps) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (data?.claims) {
    redirect("/home");
  }

  const params = await searchParams;
  const shouldCheckEmail = params.status === "check-email";

  return (
    <section className="flex flex-1 items-center px-5 py-10 sm:px-8">
      <Surface className="mx-auto w-full max-w-md p-6 sm:p-8" variant="elevated">
        <p className="text-sm font-medium text-brand-primary-hover">はじめまして</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight text-text-primary">
          {shouldCheckEmail ? "あと少しで登録完了です" : "新規登録"}
        </h1>
        <p className="mt-3 text-sm leading-6 text-text-secondary">
          {shouldCheckEmail
            ? "確認メールを送信しました。"
            : "メールアドレスとパスワードで、日記を始める準備をします。"}
        </p>

        {shouldCheckEmail ? (
          <div
            aria-live="polite"
            className="mt-7 border-t border-border-subtle pt-6"
            role="status"
          >
            <h2 className="text-lg font-semibold text-text-primary">
              次にすること
            </h2>
            <p className="mt-2 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
              メールにあるリンクを開いて、登録を完了してください。
            </p>
            <div className="mt-6 border-t border-border-subtle pt-4">
              <ActionLink className="w-full" href="/login" variant="quiet">
                ログイン画面へ
              </ActionLink>
            </div>
          </div>
        ) : (
          <AuthForm action={signUp} mode="sign-up" />
        )}
      </Surface>
    </section>
  );
}
