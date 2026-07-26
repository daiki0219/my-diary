import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { logout } from "@/app/auth/actions";
import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import { getTimelinePosts } from "@/lib/post-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "タイムライン",
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

  const [{ data: posts, error: postsError }, params] = await Promise.all([
    getTimelinePosts(supabase),
    searchParams,
  ]);

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <div className="rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">
            みんなの新しい記録
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            タイムライン
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            あなたが閲覧できる日記を、新しい順に表示します。
          </p>
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <Link
              className="rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/posts/new"
            >
              日記を書く
            </Link>
            <Link
              className="rounded-full border border-orange-300 bg-white px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/profile/posts"
            >
              自分の日記
            </Link>
          </div>
          <Link
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/profile"
          >
            プロフィール
          </Link>
        </div>

        {params.error === "logout-failed" && (
          <p
            className="mt-5 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
            role="alert"
          >
            ログアウトに失敗しました。時間をおいてもう一度お試しください。
          </p>
        )}

        {postsError ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              日記を読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : posts && posts.length > 0 ? (
          <div className="mt-5 space-y-4">
            {posts.map((post) => (
              <TimelinePostCard key={post.id} post={post} />
            ))}
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              まだ表示できる日記がありません
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-500">
              最初の日記を、気軽に書いてみましょう。
            </p>
            <Link
              className="mt-5 inline-flex rounded-full border border-orange-300 bg-orange-50 px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/posts/new"
            >
              最初の日記を書く
            </Link>
          </div>
        )}

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
