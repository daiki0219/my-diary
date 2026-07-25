import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { signUp } from "@/app/auth/actions";
import { AuthForm } from "@/components/auth/auth-form";
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
      <div className="mx-auto w-full max-w-md rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8">
        <p className="text-sm font-medium text-orange-700">はじめまして</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
          新規登録
        </h1>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          メールアドレスとパスワードで、日記を始める準備をします。
        </p>

        {shouldCheckEmail && (
          <p
            aria-live="polite"
            className="mt-5 rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm leading-6 text-green-800"
          >
            確認メールを送信しました。メール内のリンクを開いて登録を完了してください。
          </p>
        )}

        <AuthForm action={signUp} mode="sign-up" />
      </div>
    </section>
  );
}
