import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { logout } from "@/app/auth/actions";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "ホーム",
};

type HomePageProps = {
  searchParams: Promise<{
    error?: string;
  }>;
};

export default async function HomePage({ searchParams }: HomePageProps) {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub;

  if (error || !userId) {
    redirect("/login");
  }

  const [accountResult, profileResult] = await Promise.all([
    supabase
      .from("accounts")
      .select("user_id")
      .eq("user_id", userId)
      .maybeSingle(),
    supabase
      .from("profiles")
      .select("user_id")
      .eq("user_id", userId)
      .maybeSingle(),
  ]);
  const initialDataReady = Boolean(
    accountResult.data?.user_id && profileResult.data?.user_id,
  );
  const params = await searchParams;

  return (
    <section className="flex flex-1 px-5 py-10 sm:px-8">
      <div className="mx-auto w-full max-w-lg">
        <div className="rounded-3xl bg-orange-50 p-6 sm:p-8">
          <p className="text-sm font-medium text-orange-700">ログイン中</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            ホーム
          </h1>
          <p className="mt-4 leading-7 text-stone-600">
            認証が完了しました。ここはログイン済みの方だけが閲覧できるページです。
          </p>
        </div>

        {params.error === "logout-failed" && (
          <p
            className="mt-5 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
            role="alert"
          >
            ログアウトに失敗しました。時間をおいてもう一度お試しください。
          </p>
        )}

        <div className="mt-6 rounded-3xl border border-stone-200 bg-white p-6">
          <h2 className="font-semibold text-stone-800">初期データの状態</h2>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            accounts / profiles:
            <span
              className={`ml-2 font-semibold ${
                initialDataReady ? "text-green-700" : "text-amber-700"
              }`}
            >
              {initialDataReady ? "作成済み" : "確認できません"}
            </span>
          </p>
          {!initialDataReady && (
            <p className="mt-2 text-xs leading-5 text-stone-500">
              登録直後の場合は再読み込みしてください。続く場合はAuthトリガーとRLSを確認します。
            </p>
          )}
        </div>

        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <Link
            className="rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/posts/new"
          >
            日記を書く
          </Link>
          <Link
            className="rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/profile/posts"
          >
            自分の日記
          </Link>
        </div>

        <Link
          className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
          href="/profile"
        >
          プロフィールを見る
        </Link>

        <form action={logout} className="mt-8">
          <button
            className="w-full rounded-full border border-stone-300 bg-white px-5 py-3 font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            type="submit"
          >
            ログアウト
          </button>
        </form>
      </div>
    </section>
  );
}
