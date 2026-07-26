import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { PostCard } from "@/components/posts/post-card";
import { getOwnPosts } from "@/lib/post-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "自分の日記",
};

type OwnPostsPageProps = {
  searchParams: Promise<{
    status?: string;
  }>;
};

export default async function OwnPostsPage({
  searchParams,
}: OwnPostsPageProps) {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    redirect("/login");
  }

  const [{ data: posts, error: postsError }, params] = await Promise.all([
    getOwnPosts(supabase, userId),
    searchParams,
  ]);

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/profile"
        >
          ← プロフィールへ戻る
        </Link>

        <div className="mt-5 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">これまでの記録</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            自分の日記
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            公開範囲にかかわらず、あなたの未削除の日記を新しい順に表示します。
          </p>
          <Link
            className="mt-5 inline-flex rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/posts/new"
          >
            日記を書く
          </Link>
        </div>

        {params.status === "created" && (
          <p
            aria-live="polite"
            className="mt-5 rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800"
            role="status"
          >
            日記を投稿しました。
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
              <PostCard key={post.id} post={post} />
            ))}
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              まだ日記はありません
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
      </div>
    </section>
  );
}
