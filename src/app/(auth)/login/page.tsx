import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { login } from "@/app/auth/actions";
import { AuthForm } from "@/components/auth/auth-form";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "ログイン",
};

type LoginPageProps = {
  searchParams: Promise<{
    error?: string;
    status?: string;
  }>;
};

export default async function LoginPage({ searchParams }: LoginPageProps) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (data?.claims) {
    redirect("/home");
  }

  const params = await searchParams;
  const message =
    params.status === "signed-out"
      ? "ログアウトしました。"
      : params.error === "confirmation-failed"
        ? "メール確認を完了できませんでした。確認メールのリンクをもう一度お試しください。"
        : null;

  return (
    <section className="flex flex-1 items-center px-5 py-10 sm:px-8">
      <div className="mx-auto w-full max-w-md rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8">
        <p className="text-sm font-medium text-orange-700">おかえりなさい</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
          ログイン
        </h1>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          日記を続けるために、登録したメールアドレスでログインしてください。
        </p>

        {message && (
          <p
            aria-live="polite"
            className="mt-5 rounded-2xl bg-stone-100 px-4 py-3 text-sm leading-6 text-stone-700"
          >
            {message}
          </p>
        )}

        <AuthForm action={login} mode="login" />
      </div>
    </section>
  );
}
